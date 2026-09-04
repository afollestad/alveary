import Foundation
import XCTest

@testable import Alveary

@MainActor
extension GitHubAttachmentUploadServiceTests {
    static let firstAssetID = "11111111-1111-1111-1111-111111111111"
    static let secondAssetID = "22222222-2222-2222-2222-222222222222"

    static func assetURL(_ id: String) -> String {
        "https://github.com/user-attachments/assets/\(id)"
    }

    func makeService(_ shell: any ShellRunner, path: String? = "/opt/homebrew/bin/gh") -> DefaultGitHubAttachmentUploadService {
        DefaultGitHubAttachmentUploadService(
            shellRunner: shell,
            executableResolver: PullRequestsExecutablePathResolverFake(path: path)
        )
    }

    func enqueuePreflight(_ shell: MockShellRunner, version: String = "2.99.0", push: Bool = true) async {
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "gh version \(version) (2026-09-01)")))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{\"id\":42,\"permissions\":{\"push\":\(push)}}")))
    }

    func enqueueAsset(_ shell: MockShellRunner, id: String = firstAssetID) async {
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{\"url\":\"\(Self.assetURL(id))\"}")))
    }

    func file(named name: String = "a.png", size: Int = 1) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return url
    }
}

/// Cancels just as the first confirmed upload returns, exercising preservation before the next iteration.
actor CancellingAttachmentShellRunner: ShellRunner {
    private(set) var callCount = 0

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        callCount += 1
        switch callCount {
        case 1:
            return pullRequestsShellResult(stdout: "gh version 2.99.0")
        case 2:
            return pullRequestsShellResult(stdout: #"{"id":42,"permissions":{"push":true}}"#)
        default:
            withUnsafeCurrentTask { $0?.cancel() }
            return pullRequestsShellResult(stdout: #"{"url":"https://github.com/user-attachments/assets/11111111-1111-1111-1111-111111111111"}"#)
        }
    }
}
