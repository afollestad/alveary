@testable import Alveary
import Foundation
import XCTest

final class VoiceInputPinnedModelDownloaderTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputPinnedDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testPinnedURLUsesResolveCommitAndNeverMain() {
        let url = PinnedVoiceInputModelDownloader.artifactURL(
            repository: VoiceInputPinnedModelDescriptor.expectedRepository,
            revision: "4252711f6f060f9a2f91e5f081a806d7f45eebd8",
            path: "directory/file name.bin"
        ).absoluteString

        XCTAssertTrue(url.contains("/resolve/4252711f6f060f9a2f91e5f081a806d7f45eebd8/"))
        XCTAssertTrue(url.hasSuffix("directory/file%20name.bin"))
        XCTAssertFalse(url.contains("resolve/main"))
        XCTAssertFalse(url.contains("tree/main"))
    }

    func testContentRangeValidationRequiresExactStartAndTotal() {
        XCTAssertTrue(VoiceInputHTTPContentRange.isValid("bytes 3-5/6", matchesStart: 3, total: 6))
        XCTAssertFalse(VoiceInputHTTPContentRange.isValid("bytes 2-5/6", matchesStart: 3, total: 6))
        XCTAssertFalse(VoiceInputHTTPContentRange.isValid("bytes 3-5/7", matchesStart: 3, total: 6))
        XCTAssertFalse(VoiceInputHTTPContentRange.isValid("invalid", matchesStart: 3, total: 6))
        XCTAssertFalse(VoiceInputHTTPContentRange.isValid(nil, matchesStart: 3, total: 6))
    }

    func testRangeResumeRequiresAndCompletesPinnedPart() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try seedPart(Data("abc".utf8), fixture: fixture)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 206, data: Data("def".utf8), headers: [:], finalURL: secureURL)
        ])
        let downloader = makeDownloader(transport: transport)

        try await downloader.download(descriptor: fixture.descriptor, to: temporaryDirectory) { _ in }

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testServerIgnoringRangeTruncatesAndRestartsArtifact() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try seedPart(Data("abc".utf8), fixture: fixture)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=3-")
    }

    func testInvalidContentRangePurgesIncompatiblePart() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try seedPart(Data("abc".utf8), fixture: fixture)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [.invalidContentRange])

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: fixture.descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected invalid byte-range failure")
        } catch is VoiceInputInvalidContentRangeError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testValidatedCompletedArtifactIsReusedWithoutHTTP() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try fixture.data.write(to: fixture.finalURL)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
    }

    func testValidatedCompletedPartIsPromotedAndStaleSiblingIsRemovedWithoutHTTP() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try seedPart(fixture.data, fixture: fixture)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [])
        let downloader = makeDownloader(transport: transport)

        try await downloader.download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))

        try seedPart(Data("stale".utf8), fixture: fixture)
        try await downloader.download(descriptor: fixture.descriptor, to: temporaryDirectory) { _ in }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testTransientFailureResumesAndRetryAfterIsHonored() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .failure(code: .networkConnectionLost, data: Data("abc".utf8)),
            .response(status: 429, data: Data(), headers: ["retry-after": "2"], finalURL: secureURL),
            .response(status: 206, data: Data("def".utf8), headers: [:], finalURL: secureURL)
        ])
        let sleeper = VoiceInputDownloadRetrySleeperFake()
        let downloader = makeDownloader(transport: transport, sleeper: sleeper)

        try await downloader.download(descriptor: fixture.descriptor, to: temporaryDirectory) { _ in }

        let requests = await transport.requests
        let delays = await sleeper.delays
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertEqual(delays, [0.5, 2])
    }

    func testTransientHTTPFailureStopsAfterFourAttempts() async {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: Array(
            repeating: .response(status: 503, data: Data(), headers: [:], finalURL: secureURL),
            count: 4
        ))

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: fixture.descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected retry exhaustion")
        } catch {
            // Expected.
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
    }

    func testCancellationPreservesResumablePart() async {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .cancellation(data: Data("abc".utf8))
        ])

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: fixture.descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try? Data(contentsOf: fixture.partURL), Data("abc".utf8))
    }

    func testDigestAndOversizedFailuresPurgeArtifactData() async {
        for badData in [Data("xxxxxx".utf8), Data("oversized".utf8)] {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
            let transport = ScriptedVoiceInputHTTPDownloader(actions: [
                .response(status: 200, data: badData, headers: [:], finalURL: secureURL)
            ])

            do {
                try await makeDownloader(transport: transport).download(
                    descriptor: fixture.descriptor,
                    to: temporaryDirectory
                ) { _ in }
                XCTFail("Expected validation failure")
            } catch {
                // Expected.
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
        }
    }

    func testDanglingArtifactSymlinksAreRemovedBeforeDownload() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let missingTarget = temporaryDirectory.appendingPathComponent("missing")
        try FileManager.default.createSymbolicLink(at: fixture.finalURL, withDestinationURL: missingTarget)
        try FileManager.default.createSymbolicLink(at: fixture.partURL, withDestinationURL: missingTarget)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testRepositoryRootSymlinkIsReplacedWithoutTouchingExternalTarget() async throws {
        let data = Data("abcdef".utf8)
        let descriptor = makeVoiceInputTestModelDescriptor(dataByPath: ["model.bin": data]).resolved.descriptor
        let repository = temporaryDirectory.appendingPathComponent("staging/repository", isDirectory: true)
        let external = temporaryDirectory.appendingPathComponent("external", isDirectory: true)
        let sentinel = external.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: repository.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: repository, withDestinationURL: external)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: descriptor,
            to: repository
        ) { _ in }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.appendingPathComponent("model.bin").path))
        XCTAssertEqual(try Data(contentsOf: repository.appendingPathComponent("model.bin")), data)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: repository.path)[.type] as? FileAttributeType,
            .typeDirectory
        )
    }

    func testRepeatedIncompleteResponsesEventuallyPurgePart() async {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let actions = (0..<4).map { _ in
            ScriptedVoiceInputHTTPDownloader.Action.response(
                status: 200,
                data: Data("abc".utf8),
                headers: [:],
                finalURL: secureURL
            )
        }
        let transport = ScriptedVoiceInputHTTPDownloader(actions: actions)

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: fixture.descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected incomplete artifact failure")
        } catch {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testUnexpectedHiddenStagingFileIsRemoved() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let unexpected = temporaryDirectory.appendingPathComponent(".unexpected")
        try Data("unexpected".utf8).write(to: unexpected)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpected.path))
    }

    func testProgressIsMonotonicAndCompletes() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])
        let progress = VoiceInputDoubleRecorder()

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory,
            progress: progress.append
        )

        XCTAssertEqual(progress.values, progress.values.sorted())
        XCTAssertEqual(progress.values.last, 1)
    }

    func testInsecureRedirectIsRejected() async {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(
                status: 200,
                data: fixture.data,
                headers: [:],
                finalURL: URL(string: "http://example.com/model.bin")!
            )
        ])

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: fixture.descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected insecure redirect failure")
        } catch let error as VoiceInputServiceError {
            guard case .modelDownload = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    var secureURL: URL {
        URL(string: "https://cdn-lfs.huggingface.co/model.bin")!
    }

    func makeDownloader(
        transport: ScriptedVoiceInputHTTPDownloader,
        sleeper: any VoiceInputDownloadRetrySleeping = VoiceInputDownloadRetrySleeperFake()
    ) -> PinnedVoiceInputModelDownloader {
        PinnedVoiceInputModelDownloader(
            httpDownloader: transport,
            retrySleeper: sleeper
        )
    }

    func makeSingleArtifactFixture(data: Data) -> VoiceInputDownloaderFixture {
        let model = makeVoiceInputTestModelDescriptor(dataByPath: ["model.bin": data])
        let finalURL = temporaryDirectory.appendingPathComponent("model.bin")
        return VoiceInputDownloaderFixture(
            descriptor: model.resolved.descriptor,
            data: data,
            finalURL: finalURL,
            partURL: finalURL.appendingPathExtension("part")
        )
    }

    func seedPart(_ data: Data, fixture: VoiceInputDownloaderFixture) throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try data.write(to: fixture.partURL)
    }
}

struct VoiceInputDownloaderFixture {
    let descriptor: VoiceInputPinnedModelDescriptor
    let data: Data
    let finalURL: URL
    let partURL: URL
}

actor ScriptedVoiceInputHTTPDownloader: VoiceInputHTTPDownloading {
    enum Action: Sendable {
        case response(status: Int, data: Data, headers: [String: String], finalURL: URL)
        case failure(code: URLError.Code, data: Data)
        case cancellation(data: Data)
        case invalidContentRange
    }

    private var actions: [Action]
    private(set) var requests: [URLRequest] = []

    init(actions: [Action]) {
        self.actions = actions
    }

    func download(
        request: URLRequest,
        to partialURL: URL,
        expectedSize: Int64,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> VoiceInputHTTPDownloadResult {
        requests.append(request)
        guard !actions.isEmpty else {
            let attributes = try? FileManager.default.attributesOfItem(atPath: partialURL.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue
            let ranges = requests.compactMap { $0.value(forHTTPHeaderField: "Range") }
            throw VoiceInputServiceError.modelDownload(
                "Unexpected HTTP request; existing is \(existingBytes), partial is \(size ?? -1), ranges are \(ranges)."
            )
        }
        let action = actions.removeFirst()
        switch action {
        case .response(let status, let data, let headers, let finalURL):
            if status == 200 || status == 206 {
                try write(data, to: partialURL, offset: status == 206 ? existingBytes : nil)
                let attributes = try FileManager.default.attributesOfItem(atPath: partialURL.path)
                let writtenSize = (attributes[.size] as? NSNumber)?.intValue
                let expectedWrittenSize = (status == 206 ? Int(existingBytes) : 0) + data.count
                guard writtenSize == expectedWrittenSize else {
                    throw VoiceInputServiceError.modelDownload(
                        "Test transport wrote \(writtenSize ?? -1) bytes instead of \(expectedWrittenSize)."
                    )
                }
                progress(Int64(expectedWrittenSize))
            }
            return VoiceInputHTTPDownloadResult(statusCode: status, headers: headers, finalURL: finalURL)
        case .failure(let code, let data):
            try write(data, to: partialURL, offset: existingBytes)
            progress(existingBytes + Int64(data.count))
            throw URLError(code)
        case .cancellation(let data):
            try write(data, to: partialURL, offset: existingBytes)
            progress(existingBytes + Int64(data.count))
            throw CancellationError()
        case .invalidContentRange:
            throw VoiceInputInvalidContentRangeError()
        }
    }

    private func write(_ data: Data, to url: URL, offset: Int64?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let offset {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }
}

actor VoiceInputDownloadRetrySleeperFake: VoiceInputDownloadRetrySleeping {
    private(set) var delays: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        delays.append(seconds)
    }
}

private final class VoiceInputDoubleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}
