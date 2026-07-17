@testable import Alveary
import Foundation
import XCTest

extension VoiceInputPinnedModelDownloaderTests {
    func testDownloaderRejectsOverflowingDirectDescriptorWithoutTrapping() async {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let artifact = VoiceInputModelArtifact(
            path: "first.bin",
            size: .max,
            digestType: .sha256,
            digest: String(repeating: "0", count: 64)
        )
        let descriptor = VoiceInputPinnedModelDescriptor(
            formatVersion: fixture.descriptor.formatVersion,
            repository: fixture.descriptor.repository,
            revision: fixture.descriptor.revision,
            configuration: fixture.descriptor.configuration,
            artifacts: [
                artifact,
                VoiceInputModelArtifact(
                    path: "second.bin",
                    size: 1,
                    digestType: .sha256,
                    digest: String(repeating: "0", count: 64)
                )
            ]
        )
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [])

        do {
            try await makeDownloader(transport: transport).download(
                descriptor: descriptor,
                to: temporaryDirectory
            ) { _ in }
            XCTFail("Expected invalid descriptor size failure")
        } catch let error as VoiceInputServiceError {
            guard case .modelCache = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testUnsatisfiableRangePurgesPartAndRestartsFromZero() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        try seedPart(Data("abc".utf8), fixture: fixture)
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .response(status: 416, data: Data(), headers: [:], finalURL: secureURL),
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Range"))
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
    }

    func testUnsatisfiableRangeOnFinalRetryRestartsWithoutConsumingRetryBudget() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .failure(code: .networkConnectionLost, data: Data("abc".utf8)),
            .response(status: 503, data: Data(), headers: [:], finalURL: secureURL),
            .response(status: 503, data: Data(), headers: [:], finalURL: secureURL),
            .response(status: 416, data: Data(), headers: [:], finalURL: secureURL),
            .response(status: 200, data: fixture.data, headers: [:], finalURL: secureURL)
        ])
        let sleeper = VoiceInputDownloadRetrySleeperFake()

        try await makeDownloader(transport: transport, sleeper: sleeper).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        let requests = await transport.requests
        let delays = await sleeper.delays
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "Range"), "bytes=3-")
        XCTAssertNil(requests[4].value(forHTTPHeaderField: "Range"))
        XCTAssertEqual(delays, [0.5, 1, 2])
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
    }

    func testTransientFailureAfterCompleteWritePromotesPartWithoutAnotherRequest() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .failure(code: .networkConnectionLost, data: fixture.data)
        ])

        try await makeDownloader(transport: transport).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }

    func testCompleteWriteOnFinalTransientAttemptPromotesPart() async throws {
        let fixture = makeSingleArtifactFixture(data: Data("abcdef".utf8))
        let transport = ScriptedVoiceInputHTTPDownloader(actions: [
            .failure(code: .networkConnectionLost, data: Data("a".utf8)),
            .failure(code: .networkConnectionLost, data: Data("b".utf8)),
            .failure(code: .networkConnectionLost, data: Data("c".utf8)),
            .failure(code: .networkConnectionLost, data: Data("def".utf8))
        ])
        let sleeper = VoiceInputDownloadRetrySleeperFake()

        try await makeDownloader(transport: transport, sleeper: sleeper).download(
            descriptor: fixture.descriptor,
            to: temporaryDirectory
        ) { _ in }

        let requests = await transport.requests
        let delays = await sleeper.delays
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(delays, [0.5, 1, 2])
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partURL.path))
    }
}
