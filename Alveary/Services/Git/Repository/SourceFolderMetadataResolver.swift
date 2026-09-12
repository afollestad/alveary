import Foundation

/// Captures Git context for an added grant without changing the directory the user granted.
/// Metadata is advisory; a failed probe never removes the grant or substitutes another folder.
struct SourceFolderMetadataResolver: Sendable {
    var shell: any ShellRunner = DefaultShellRunner()

    func resolve(path: String) async -> SourceFolderSnapshot {
        var source = SourceFolderSnapshot(path: path)
        guard let branch = await output(["rev-parse", "--abbrev-ref", "HEAD"], in: path) else { return source }
        source.gitBranch = branch
        var remote = await output(["for-each-ref", "--format=%(upstream:remotename)", "refs/heads/\(branch)"], in: path)
        if remote == nil {
            let remotes = (await output(["remote"], in: path))?.split(separator: "\n").map(String.init) ?? []
            remote = remotes.contains("origin") ? "origin" : (remotes.count == 1 ? remotes.first : nil)
        }
        source.remoteName = remote
        if let remote {
            source.gitRemote = await output(["remote", "get-url", remote], in: path)
            if let head = await output(["symbolic-ref", "refs/remotes/\(remote)/HEAD"], in: path) {
                let prefix = "refs/remotes/\(remote)/"
                if head.hasPrefix(prefix) { source.baseRef = String(head.dropFirst(prefix.count)) }
            }
        }
        source.baseRef = source.baseRef ?? branch
        source.githubRepository = source.gitRemote.flatMap(Project.parseGitHubRepository)
        return source
    }

    private func output(_ args: [String], in path: String) async -> String? {
        guard !Task.isCancelled,
              let result = try? await shell.run(
                executable: "/usr/bin/git", args: args, in: path, timeout: .seconds(10),
                stdoutLimitBytes: 64 * 1024, stderrLimitBytes: 64 * 1024, standardInput: .nullDevice
              ), result.succeeded, !result.stdoutWasTruncated else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
