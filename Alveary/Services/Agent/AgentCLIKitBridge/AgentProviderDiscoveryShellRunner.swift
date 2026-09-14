import AgentCLIKit
import Foundation

/// Discovery commands need no input and must release their whole process group when a CLI or login-shell startup stalls.
/// Kept separate from `AgentCLIKitShellRunnerAdapter` so provider turns and other SDK commands retain their existing budgets.
struct AgentProviderDiscoveryShellRunner: AgentCLIKit.ShellRunning {
    let shellRunner: any ShellRunner
    let timeout: Duration

    init(shellRunner: any ShellRunner, timeout: Duration = .seconds(5)) {
        self.shellRunner = shellRunner
        self.timeout = timeout
    }

    func run(_ command: AgentCLIKit.ShellCommand) async throws -> AgentCLIKit.ShellCommandResult {
        let result = try await shellRunner.run(
            executable: command.executable,
            args: command.arguments,
            in: command.workingDirectory?.path,
            options: ShellRunOptions(
                environment: command.environment.isEmpty ? nil : command.environment,
                processGroupPolicy: .create,
                timeout: timeout,
                stdoutLimitBytes: 256 * 1024,
                stderrLimitBytes: 256 * 1024,
                standardInput: .nullDevice
            )
        )
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw AgentProviderDiscoveryShellError.outputTooLarge
        }
        return AgentCLIKit.ShellCommandResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    }
}

/// A partial version, path, or feature list must never become a plausible discovery result.
enum AgentProviderDiscoveryShellError: Error {
    case outputTooLarge
}
