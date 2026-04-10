import Foundation

final class DefaultAgentEnvironmentBuilder: AgentEnvironmentBuilder, Sendable {
    func buildEnvironment(providerEnv: [String: String]? = nil) -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        var result: [String: String] = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "Skep",
            "HOME": environment["HOME"] ?? NSHomeDirectory(),
            "USER": environment["USER"] ?? NSUserName(),
            "PATH": environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin",
            "LANG": environment["LANG"] ?? "en_US.UTF-8"
        ]

        for key in ["TMPDIR", "SSH_AUTH_SOCK"] {
            if let value = environment[key] {
                result[key] = value
            }
        }

        for key in agentEnvVars {
            if let value = environment[key] {
                result[key] = value
            }
        }

        if let providerEnv {
            for (key, value) in providerEnv {
                result[key] = value
            }
        }

        return result
    }

    private let agentEnvVars = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "OPENAI_API_KEY",
        "OPENAI_ORG_ID",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_ENDPOINT",
        "GEMINI_API_KEY",
        "GOOGLE_API_KEY",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "VERTEX_PROJECT",
        "VERTEX_LOCATION",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "AWS_REGION",
        "AWS_DEFAULT_REGION",
        "AWS_PROFILE",
        "GITHUB_TOKEN",
        "GH_TOKEN",
        "MISTRAL_API_KEY",
        "COHERE_API_KEY",
        "XAI_API_KEY",
        "FIREWORKS_API_KEY",
        "TOGETHER_API_KEY",
        "PERPLEXITY_API_KEY",
        "DEEPSEEK_API_KEY",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "NO_PROXY",
        "ALL_PROXY",
        "SSL_CERT_FILE",
        "REQUESTS_CA_BUNDLE"
    ]
}
