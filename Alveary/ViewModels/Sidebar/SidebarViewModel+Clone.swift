import Foundation

extension SidebarViewModel {
    func cloneRepository(
        url: String,
        into destinationPath: String,
        branch: String?
    ) async throws -> Project {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let expandedDestination = (destinationPath as NSString).expandingTildeInPath

        if trimmedURL.isEmpty {
            throw GitError.commandFailed("Repository URL is required.")
        }

        // Refuse to clone over an existing path so the cleanup invariant on failure
        // — "remove only what we created" — always holds.
        if FileManager.default.fileExists(atPath: expandedDestination) {
            throw GitError.commandFailed("Destination already exists: \(expandedDestination)")
        }

        // Snapshot the deepest already-existing ancestor before we mkdir -p any
        // intermediate directories. On failure we walk back up to (but not into)
        // this ancestor, so user-owned folders like `~/Development` are preserved
        // while folders the clone created itself are removed.
        let preExistingAncestor = Self.deepestExistingAncestor(of: expandedDestination)

        do {
            let parent = (expandedDestination as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: parent,
                withIntermediateDirectories: true
            )

            var args = ["clone", trimmedURL, expandedDestination]
            let trimmedBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedBranch, !trimmedBranch.isEmpty {
                args.append(contentsOf: ["--branch", trimmedBranch, "--single-branch"])
            }

            _ = try await gitOutput(args: args, in: nil)
            return try await createProject(path: expandedDestination)
        } catch {
            await Self.detachedCloneCleanup(
                destinationPath: expandedDestination,
                preExistingAncestor: preExistingAncestor
            )
            throw error
        }
    }

    // Detached so a cancelled caller cannot abort the filesystem cleanup —
    // mirrors `DefaultWorktreeManager.detachedCleanupAfterFailedCreate`.
    private static func detachedCloneCleanup(
        destinationPath: String,
        preExistingAncestor: String
    ) async {
        await Task.detached {
            try? FileManager.default.removeItem(atPath: destinationPath)

            // Walk up removing any intermediate directories `createDirectory`
            // created. Stop at the first directory that pre-existed, and only
            // remove empty directories so we never clobber a sibling project the
            // user dropped into the same parent between the start and end of the
            // clone.
            var current = (destinationPath as NSString).deletingLastPathComponent
            while current != preExistingAncestor,
                  current != "/",
                  !current.isEmpty {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: current)) ?? []
                guard contents.isEmpty else {
                    break
                }
                try? FileManager.default.removeItem(atPath: current)
                current = (current as NSString).deletingLastPathComponent
            }
        }.value
    }

    private static func deepestExistingAncestor(of path: String) -> String {
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty, current != "/" {
            if FileManager.default.fileExists(atPath: current) {
                return current
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return "/"
    }
}
