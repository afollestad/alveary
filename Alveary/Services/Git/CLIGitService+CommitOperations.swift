import Foundation

extension CLIGitService {
    func hasStagedChanges(in directory: String) async throws -> Bool {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["diff", "--cached", "--quiet", "--exit-code"],
            in: directory
        )
        if result.exitCode == 0 {
            return false
        }
        if result.exitCode == 1 {
            return true
        }
        throw Self.makeError(from: result)
    }

    func validateBranchName(_ branchName: String, in directory: String) async throws -> Bool {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranchName.isEmpty else {
            return false
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["check-ref-format", "--branch", trimmedBranchName],
            in: directory
        )
        return result.succeeded
    }

    func checkoutNewBranch(_ branchName: String, in directory: String) async throws {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranchName.isEmpty else {
            throw GitError.commandFailed("Branch name cannot be empty")
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["checkout", "-b", trimmedBranchName],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func commit(message: String, includeUnstagedChanges: Bool, in directory: String) async throws {
        if includeUnstagedChanges {
            let addResult = try await shell.run(
                executable: "/usr/bin/git",
                args: ["add", "--all"],
                in: directory
            )
            guard addResult.succeeded else {
                throw Self.makeError(from: addResult)
            }
        }

        let messageFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-commit-message-\(UUID().uuidString)")
        try message.write(to: messageFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: messageFileURL) }

        let commitResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["commit", "--cleanup=verbatim", "--file", messageFileURL.path],
            in: directory
        )
        guard commitResult.succeeded else {
            throw Self.makeError(from: commitResult)
        }
    }

    func pushCurrentBranch(remoteName: String?, in directory: String) async throws {
        let branch = try await currentBranch(in: directory)
        let remote = remoteName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "origin"
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["push", "-u", remote, branch],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
