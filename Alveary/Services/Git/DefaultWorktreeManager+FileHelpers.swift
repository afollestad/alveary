import Darwin
import Foundation

extension DefaultWorktreeManager {
    func preserveFiles(from source: String, to destination: String, patterns configPatterns: [String]?) throws {
        let patterns = configPatterns ?? [".env", ".env.local", ".env.development"]
        let sourceURL = URL(fileURLWithPath: source)
        let destinationURL = URL(fileURLWithPath: destination)
        let fileManager = FileManager.default

        for pattern in patterns {
            let fullPattern = sourceURL.appendingPathComponent(pattern).path
            var globResult = glob_t()
            defer { globfree(&globResult) }

            guard glob(fullPattern, 0, nil, &globResult) == 0 else {
                continue
            }

            for index in 0..<Int(globResult.gl_pathc) {
                guard let matchPointer = globResult.gl_pathv[index],
                      let matchedPath = String(validatingCString: matchPointer) else {
                    continue
                }

                let relativePath = String(matchedPath.dropFirst(sourceURL.path.count + 1))
                let destinationPath = destinationURL.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: destinationPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationPath.path) {
                    try? fileManager.removeItem(at: destinationPath)
                }
                try? fileManager.copyItem(atPath: matchedPath, toPath: destinationPath.path)
            }
        }
    }

    func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst(9))
            } else if line.hasPrefix("branch refs/heads/") {
                currentBranch = String(line.dropFirst(18))
            } else if line.isEmpty {
                if let currentPath, let currentBranch {
                    worktrees.append(WorktreeInfo(path: currentPath, branch: currentBranch))
                }
                currentPath = nil
                currentBranch = nil
            }
        }

        if let currentPath, let currentBranch {
            worktrees.append(WorktreeInfo(path: currentPath, branch: currentBranch))
        }

        return worktrees
    }
}
