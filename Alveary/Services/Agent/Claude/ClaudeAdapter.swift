import Foundation

final class ClaudeAdapter: AgentAdapter, Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = true
    let localCommandCaveatStartTag = "<local-command-caveat>"
    let localCommandCaveatEndTag = "</local-command-caveat>"
    let hasDeferredTool = LockedState(false)

    func buildArgs(config: AgentConfig) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]

        if let permissionMode = config.permissionMode {
            args += ["--permission-mode", permissionMode]
        }
        if let model = config.model {
            args += ["--model", model]
        }
        if let effort = config.effort {
            args += ["--effort", effort]
        }

        return args
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let event: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": message]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw AgentError.spawnFailed("Failed to encode message as UTF-8")
        }

        try stdin.fileHandleForWriting.write(contentsOf: Data((payload + "\n").utf8))
    }

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        let canonicalCwd = CanonicalPath.normalize(cwd)
        let encodedDirectory = ClaudePathEncoding.projectDirectoryName(forCanonicalCwd: canonicalCwd)
        return NSHomeDirectory() + "/.claude/projects/\(encodedDirectory)/\(sessionId).jsonl"
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        guard let path = sessionFilePath(sessionId: sessionId, cwd: cwd) else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        if isResuming, canResumeSession(sessionId: sessionId, cwd: cwd) {
            var args = ["--resume", sessionId]
            if forkSession {
                args.append("--fork-session")
            }
            return SessionLaunchDecision(args: args, continuity: .preserved)
        }

        return SessionLaunchDecision(
            args: ["--session-id", sessionId],
            continuity: isResuming ? .restartedFresh : .preserved
        )
    }
}
