import Foundation

struct TempDeferredToolExecutable {
    enum EventStyle {
        case result
        case hookAttachment
    }

    let directory: URL
    let url: URL
    let workingDirectory: URL

    init(
        eventStyle: EventStyle = .result,
        emitsTrailingAssistantMessage: Bool = false,
        trailingDelaySeconds: Double = 1
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("deferred-tool-agent.sh")
        workingDirectory = directory.appendingPathComponent("project", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data(
            script(
                eventStyle: eventStyle,
                emitsTrailingAssistantMessage: emitsTrailingAssistantMessage,
                trailingDelaySeconds: trailingDelaySeconds
            ).utf8
        )
            .write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(
        eventStyle: EventStyle,
        emitsTrailingAssistantMessage: Bool,
        trailingDelaySeconds: Double
    ) -> String {
        """
        #!/bin/sh
        cat <<'EOF' | /usr/bin/tr -d '\\n'
        \(deferredEventJSON(eventStyle: eventStyle))
        EOF
        /usr/bin/printf '\\n'
        \(trailingAssistantMessageScript(enabled: emitsTrailingAssistantMessage, delaySeconds: trailingDelaySeconds))
        /bin/sleep 30
        """
    }

    private func deferredEventJSON(eventStyle: EventStyle) -> String {
        switch eventStyle {
        case .result:
            return resultEventJSON()
        case .hookAttachment:
            return hookAttachmentEventJSON()
        }
    }

    private func resultEventJSON() -> String {
        """
        {
          "type": "result",
          "subtype": "success",
          "stop_reason": "tool_deferred",
          "session_id": "session-deferred",
          "deferred_tool_use": {
            "id": "toolu_deferred",
            "name": "AskUserQuestion",
            "input": {
              \(questionsJSON())
            }
          },
          "usage": {
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_input_tokens": 0
          },
          "duration_ms": 1,
          "total_cost_usd": 0,
          "is_error": false
        }
        """
    }

    private func hookAttachmentEventJSON() -> String {
        """
        {
          "type": "attachment",
          "sessionId": "session-deferred",
          "attachment": {
            "type": "hook_deferred_tool",
            "toolUseID": "toolu_deferred",
            "toolName": "AskUserQuestion",
            "toolInput": {
              \(questionsJSON())
            }
          }
        }
        """
    }

    private func questionsJSON() -> String {
        """
        "questions": [{
          "question": "Pick one",
          "header": "Pick",
          "options": [{
            "label": "A",
            "description": "First"
          }],
          "multiSelect": false
        }]
        """
    }

    private func trailingAssistantMessageScript(enabled: Bool, delaySeconds: Double) -> String {
        guard enabled else {
            return ""
        }

        return """
        /bin/sleep \(delaySeconds)
        cat <<'EOF'
        {"type":"assistant","message":{"content":[{"type":"text","text":"The AskUserQuestion tool is returning internal errors on my end."}]}}
        EOF
        """
    }
}

struct TempHookServerDeferredToolExecutable {
    let directory: URL
    let url: URL
    let workingDirectory: URL

    init(trailingDelaySeconds: Double = 2) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("hook-server-deferred-tool-agent.sh")
        workingDirectory = directory.appendingPathComponent("project", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data(script(trailingDelaySeconds: trailingDelaySeconds).utf8)
            .write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(trailingDelaySeconds: Double) -> String {
        """
        #!/bin/sh
        cat <<'EOF'
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_first","name":"Bash","input":{"command":"date +%s"}}]}}
        EOF
        /bin/sleep \(trailingDelaySeconds)
        cat <<'EOF'
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_second","name":"Bash","input":{"command":"uname -a"}}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Tool calls are returning internal errors."}]}}
        EOF
        /bin/sleep 30
        """
    }
}
