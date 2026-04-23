import Foundation

struct TempDeferredToolExecutable {
    let directory: URL
    let url: URL
    let workingDirectory: URL

    init(emitsTrailingAssistantMessage: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("deferred-tool-agent.sh")
        workingDirectory = directory.appendingPathComponent("project", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data(script(emitsTrailingAssistantMessage: emitsTrailingAssistantMessage).utf8)
            .write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(emitsTrailingAssistantMessage: Bool) -> String {
        """
        #!/bin/sh
        cat <<'EOF' | /usr/bin/tr -d '\\n'
        {
          "type": "result",
          "subtype": "success",
          "stop_reason": "tool_deferred",
          "session_id": "session-deferred",
          "deferred_tool_use": {
            "id": "toolu_deferred",
            "name": "AskUserQuestion",
            "input": {
              "questions": [{
                "question": "Pick one",
                "header": "Pick",
                "options": [{
                  "label": "A",
                  "description": "First"
                }],
                "multiSelect": false
              }]
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
        EOF
        /usr/bin/printf '\\n'
        \(trailingAssistantMessageScript(enabled: emitsTrailingAssistantMessage))
        /bin/sleep 30
        """
    }

    private func trailingAssistantMessageScript(enabled: Bool) -> String {
        guard enabled else {
            return ""
        }

        return """
        /bin/sleep 1
        cat <<'EOF'
        {"type":"assistant","message":{"content":[{"type":"text","text":"The AskUserQuestion tool is returning internal errors on my end."}]}}
        EOF
        """
    }
}
