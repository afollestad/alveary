import Foundation

struct TerminalProjectActionShellIntegration {
    let markerToken: String
    let environment: [String]
    let directoryURL: URL

    static func prepare(
        configuration: TerminalLaunchConfiguration,
        sessionID: UUID,
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> TerminalProjectActionShellIntegration? {
        guard configuration.projectActionCommand != nil,
              URL(fileURLWithPath: configuration.executable).lastPathComponent == "zsh" else {
            return nil
        }

        let markerToken = UUID().uuidString.lowercased()
        let directoryURL = temporaryDirectory
            .appendingPathComponent("Alveary-TerminalAction-\(sessionID.uuidString)-\(markerToken)", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )

            let originalZDOTDIR = environmentValue(named: "ZDOTDIR", in: configuration.environment)
                ?? environmentValue(named: "HOME", in: configuration.environment)
                ?? NSHomeDirectory()
            try writeStartupFiles(markerToken: markerToken, directoryURL: directoryURL, fileManager: fileManager)

            var environment = configuration.environment.filter { entry in
                !entry.hasPrefix("ZDOTDIR=") && !entry.hasPrefix("ALVEARY_ZSH_USER_ZDOTDIR=")
            }
            environment.append("ZDOTDIR=\(directoryURL.path)")
            environment.append("ALVEARY_ZSH_USER_ZDOTDIR=\(originalZDOTDIR)")

            return TerminalProjectActionShellIntegration(
                markerToken: markerToken,
                environment: environment.sorted(),
                directoryURL: directoryURL
            )
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    func cleanup(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: directoryURL)
    }
}

enum TerminalProjectActionMarker: Equatable {
    case ready
    case completed(exitCode: Int32)

    static func parse(content: ArraySlice<UInt8>, expectedToken: String) -> TerminalProjectActionMarker? {
        guard let value = String(bytes: content, encoding: .utf8),
              value.hasPrefix("AlvearyProjectAction=\(expectedToken):") else {
            return nil
        }

        let suffix = value.dropFirst("AlvearyProjectAction=\(expectedToken):".count)
        if suffix == "ready" {
            return .ready
        }
        guard suffix.hasPrefix("complete:"),
              let exitCode = Int32(suffix.dropFirst("complete:".count)) else {
            return nil
        }
        return .completed(exitCode: exitCode)
    }
}

enum TerminalProjectActionCommandEncoder {
    static func bytes(command: String, bracketedPasteEnabled: Bool) -> [UInt8] {
        let normalizedCommand = command
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result: [UInt8] = []
        if bracketedPasteEnabled {
            result.append(contentsOf: [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E])
        }
        result.append(contentsOf: normalizedCommand.utf8)
        if bracketedPasteEnabled {
            result.append(contentsOf: [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        }
        result.append(0x0D)
        return result
    }
}

private extension TerminalProjectActionShellIntegration {
    static func writeStartupFiles(
        markerToken: String,
        directoryURL: URL,
        fileManager: FileManager
    ) throws {
        for fileName in [".zshenv", ".zprofile", ".zshrc"] {
            try writeStartupFile(
                named: fileName,
                contents: sourceUserStartupFile(named: fileName, integrationDirectory: directoryURL.path),
                directoryURL: directoryURL,
                fileManager: fileManager
            )
        }
        try writeStartupFile(
            named: ".zlogin",
            contents: zloginScript(markerToken: markerToken, integrationDirectory: directoryURL.path),
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    static func sourceUserStartupFile(named fileName: String, integrationDirectory: String) -> String {
        let integrationDirectory = shellSingleQuoted(integrationDirectory)
        return """
        typeset -g __alveary_integration_zdotdir=\(integrationDirectory)
        typeset -g __alveary_user_zdotdir="${ALVEARY_ZSH_USER_ZDOTDIR:-$HOME}"
        if [[ "$__alveary_user_zdotdir" != "$__alveary_integration_zdotdir" && -r "$__alveary_user_zdotdir/\(fileName)" ]]; then
          ZDOTDIR="$__alveary_user_zdotdir"
          source "$ZDOTDIR/\(fileName)"
          __alveary_user_zdotdir="${ZDOTDIR:-$HOME}"
        fi
        ZDOTDIR="$__alveary_integration_zdotdir"
        export ALVEARY_ZSH_USER_ZDOTDIR="$__alveary_user_zdotdir"
        unset __alveary_integration_zdotdir __alveary_user_zdotdir

        """
    }

    static func zloginScript(markerToken: String, integrationDirectory: String) -> String {
        sourceUserStartupFile(named: ".zlogin", integrationDirectory: integrationDirectory) + #"""
        typeset -gi __alveary_project_action_state=0

        function __alveary_project_action_line_init {
          if zle -l __alveary_saved_line_init >/dev/null 2>&1; then
            zle __alveary_saved_line_init "$@"
          fi
          if (( __alveary_project_action_state != 0 )); then
            return
          fi
          __alveary_project_action_state=1
          if zle -l __alveary_saved_line_init >/dev/null 2>&1; then
            zle -A __alveary_saved_line_init zle-line-init
            zle -D __alveary_saved_line_init
          else
            zle -D zle-line-init
          fi
          printf '\033]1337;AlvearyProjectAction=\#(markerToken):ready\007'
        }

        function __alveary_project_action_precmd {
          local __alveary_project_action_status=$?
          if (( __alveary_project_action_state != 1 )); then
            return
          fi
          __alveary_project_action_state=2
          precmd_functions=("${(@)precmd_functions:#__alveary_project_action_precmd}")
          printf '\033]1337;AlvearyProjectAction=\#(markerToken):complete:%d\007' "$__alveary_project_action_status"
          unset __alveary_project_action_state
          unfunction __alveary_project_action_line_init __alveary_project_action_precmd
        }

        typeset -ga precmd_functions
        precmd_functions=("${(@)precmd_functions:#__alveary_project_action_precmd}" __alveary_project_action_precmd)
        if zle -l zle-line-init >/dev/null 2>&1; then
          zle -A zle-line-init __alveary_saved_line_init
        fi
        zle -N zle-line-init __alveary_project_action_line_init

        # Restore after startup so login zsh finds the user's .zlogout on exit.
        ZDOTDIR="${ALVEARY_ZSH_USER_ZDOTDIR:-$HOME}"
        unset ALVEARY_ZSH_USER_ZDOTDIR

        """#
    }

    static func writeStartupFile(
        named fileName: String,
        contents: String,
        directoryURL: URL,
        fileManager: FileManager
    ) throws {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func environmentValue(named key: String, in environment: [String]) -> String? {
        let prefix = "\(key)="
        guard let entry = environment.last(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(entry.dropFirst(prefix.count))
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
