import AgentCLIKit
import Foundation

/// Validate CLI capabilities and frozen selections before creating a review task or starting paid work.
extension DefaultPullRequestReviewWorkerExecutor {
    private static let capabilityOutputLimitBytes = 256 * 1024
    private static let preflightRunID = "review-worker-preflight"

    /// Recheck each launch: a CLI wrapper's target can change without changing the configured executable path.
    func preflight(_ configuration: ReviewWorkerConfiguration) async throws {
        let harnessID = try Self.validatedHarnessID(configuration)
        if harnessID == .opencode {
            let adapter = try Self.adapter(for: harnessID, executablePath: configuration.executablePath)
            let prepared = try await adapter.prepareOneShotPrompt(request: .init(
                harnessId: harnessID, workingDirectory: FileManager.default.temporaryDirectory,
                prompt: "Validate the frozen review worker configuration.", environment: workerEnvironment(for: harnessID),
                model: configuration.launchModel, effort: AppSettings.openCodeNativeEffort(stored: configuration.effort),
                timeout: Self.timeoutSeconds, toolPolicy: .readOnly
            ))
            try prepared.cleanup()
            return
        }

        let result = try await capabilityOutput(configuration, harnessID: harnessID)
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw PullRequestReviewWorkerError.executableUnavailable(configuration.executablePath)
        }
        guard result.succeeded else {
            let diagnostic = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PullRequestReviewWorkerError.capabilityCheckFailed(
                harnessID: configuration.harnessID,
                exitCode: result.exitCode,
                message: ReviewTeamDiagnostics.persisted(diagnostic.isEmpty ? Self.missingDiagnostic : diagnostic)
            )
        }
        let help = [result.stdout, result.stderr].joined(separator: "\n")
        let requiredFlags = Self.requiredFlags(for: harnessID)
        let missing = requiredFlags.filter { !help.contains($0) }
        guard missing.isEmpty else {
            throw PullRequestReviewWorkerError.missingCapabilities(
                harnessID: configuration.harnessID,
                flags: missing
            )
        }
    }

    private func capabilityOutput(
        _ configuration: ReviewWorkerConfiguration, harnessID: AgentCLIKit.AgentHarnessID
    ) async throws -> ShellResult {
        let executable = harnessID == .claude ? "/usr/bin/perl" : configuration.executablePath
        let helpArguments = harnessID == .claude
            ? ["-e", Self.claudeCapabilityCaptureProgram, "--", configuration.executablePath, "--help"]
            : ["exec", "--help"]
        let processKey = PullRequestReviewWorkerProcessKey(
            runID: Self.preflightRunID,
            generation: 0,
            executionID: "\(configuration.harnessID):\(configuration.executablePath)"
        )
        let shellRunner = capabilityShellRunner
            ?? DefaultShellRunner(processTracker: processRegistry.tracker(for: processKey))
        do {
            return try await shellRunner.run(
                executable: executable,
                args: helpArguments,
                environment: workerEnvironment(for: harnessID),
                environmentPolicy: .replace,
                processGroupPolicy: .create,
                timeout: .seconds(5),
                stdoutLimitBytes: Self.capabilityOutputLimitBytes,
                stderrLimitBytes: Self.capabilityOutputLimitBytes,
                standardInput: .nullDevice
            )
        } catch let ShellError.ioFailure(failure) {
            try Task.checkCancellation()
            throw ReviewWorkerIOFailure(stage: .capabilityCheck, failure: failure, codexCompletion: nil)
        }
    }

    private static func requiredFlags(for harnessID: AgentCLIKit.AgentHarnessID) -> [String] {
        switch harnessID {
        case .claude:
            [
                "--safe-mode",
                "--no-session-persistence",
                "--restricted",
                "--strict-mcp-config",
                "--disable-slash-commands",
                "--no-chrome",
                "--permission-mode",
                "--permission-prompts",
                "dontAsk",
                "--tools"
            ]
        case .codex:
            [
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--skip-git-repo-check",
                "--strict-config",
                "--disable",
                "--sandbox"
            ]
        case .opencode:
            []
        }
    }

    /// Claude can exit before flushing piped help; anonymous files preserve it while the runner retains limits and group teardown.
    private static let claudeCapabilityCaptureProgram = #"""
    use strict;
    use File::Temp qw(tmpfile);
    my $stdout = tmpfile() or die "Could not create stdout capture: $!";
    my $stderr = tmpfile() or die "Could not create stderr capture: $!";
    my $pid = fork();
    defined($pid) or die "Could not fork capability probe: $!";
    if ($pid == 0) {
        open(STDOUT, '>&', $stdout) or die "Could not redirect stdout: $!";
        open(STDERR, '>&', $stderr) or die "Could not redirect stderr: $!";
        exec {$ARGV[0]} @ARGV;
        die "Could not launch capability probe: $!";
    }
    waitpid($pid, 0) == $pid or die "Could not wait for capability probe: $!";
    my $status = $?;
    for my $capture ([$stdout, \*STDOUT], [$stderr, \*STDERR]) {
        my ($input, $output) = @$capture;
        seek($input, 0, 0) or die "Could not rewind capability capture: $!";
        while (1) {
            my $count = read($input, my $buffer, 16384);
            defined($count) or die "Could not read capability capture: $!";
            last unless $count;
            print $output $buffer or die "Could not replay capability capture: $!";
        }
    }
    exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
    """#
}
