@testable import Alveary
import Darwin
import Foundation
import XCTest

extension VoiceInputPinnedModelDownloaderTests {
    func testOnlyExpectedArtifactDirectoriesAndRegularFilesRemain() async throws {
        let data = Data("abcdef".utf8)
        let model = makeVoiceInputTestModelDescriptor(dataByPath: ["expected/nested/model.bin": data])
        let unexpectedDirectory = temporaryDirectory.appendingPathComponent("expected/unexpected", isDirectory: true)
        let unexpectedFile = unexpectedDirectory.appendingPathComponent("file.bin")
        let unexpectedPipe = temporaryDirectory.appendingPathComponent("expected/unexpected.pipe")
        try FileManager.default.createDirectory(at: unexpectedDirectory, withIntermediateDirectories: true)
        try Data("unexpected".utf8).write(to: unexpectedFile)
        XCTAssertEqual(Darwin.mkfifo(unexpectedPipe.path, 0o600), 0)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: model.resolved.descriptor,
            to: temporaryDirectory
        ) { _ in }

        XCTAssertEqual(
            try voiceInputRelativePaths(in: temporaryDirectory),
            Set(["expected", "expected/nested", "expected/nested/model.bin"])
        )
    }

    func testStreamingDownloaderRejectsOversizedChunkBeforeWritingIt() throws {
        let partialURL = temporaryDirectory.appendingPathComponent("model.bin.part")
        let request = URLRequest(url: URL(string: "https://huggingface.co/model.bin")!)
        let delegate = VoiceInputStreamingDownloadDelegate(
            request: request,
            partialURL: partialURL,
            expectedSize: 6,
            existingBytes: 0
        ) { _ in }
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: request)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ))
        let responseWasAllowed = LockedState(false)
        delegate.urlSession(session, dataTask: task, didReceive: response) { disposition in
            responseWasAllowed.withLock { $0 = disposition == .allow }
        }

        delegate.urlSession(session, dataTask: task, didReceive: Data("oversized".utf8))
        delegate.urlSession(session, task: task, didCompleteWithError: nil)

        XCTAssertTrue(responseWasAllowed.withLock { $0 })
        XCTAssertEqual(try Data(contentsOf: partialURL), Data())
    }
}

private func voiceInputRelativePaths(in root: URL) throws -> Set<String> {
    let enumerator = try XCTUnwrap(
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    )
    let rootPath = root.standardizedFileURL.path
    var relativePaths = Set<String>()
    for case let url as URL in enumerator {
        relativePaths.insert(String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1)))
    }
    return relativePaths
}
