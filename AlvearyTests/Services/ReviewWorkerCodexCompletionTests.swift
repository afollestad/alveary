import Foundation
import XCTest

@testable import Alveary

final class ReviewWorkerCodexCompletionTests: XCTestCase {
    func testCompletedTurnRecoversWhenEitherOrBothPipesRemainOpen() {
        let failures = [
            Self.failure(),
            Self.failure(stdoutFailure: nil, stderrFailure: .drainTimedOut),
            Self.failure(stderrFailure: .drainTimedOut)
        ]
        for failure in failures {
            XCTAssertTrue(ReviewWorkerCodexCompletion.canRecover(failure))
        }
    }

    func testCompletedTurnAllowsBlankLinesCRLFAndEarlierCompletedItems() {
        let reasoning = #"{"type":"item.completed","item":{"type":"reasoning","text":"Checking the diff."}}"#
        let output = Self.stream([Self.thread, Self.started, reasoning, Self.message, Self.message, Self.completed])
        let variants = [output, "\n \t\n" + output + "\n", output.replacingOccurrences(of: "\n", with: "\r\n")]
        for variant in variants {
            XCTAssertTrue(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: Self.result(stdout: variant))), variant.debugDescription)
        }
    }

    func testProcessAndCaptureFailuresCannotRecoverDespiteCompletedTurn() {
        let failures = [
            Self.failure(exitedNormally: false),
            Self.failure(inputCompleted: false),
            Self.failure(result: Self.result(exitCode: 7)),
            Self.failure(result: Self.result(stdoutWasTruncated: true)),
            Self.failure(result: Self.result(stderrWasTruncated: true)),
            Self.failure(stdoutFailure: nil),
            Self.failure(stdoutFailure: .readFailed(5)),
            Self.failure(stderrFailure: .readFailed(5)),
            Self.failure(stdoutFailure: .readFailed(5), stderrFailure: .drainTimedOut)
        ]
        for failure in failures {
            XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(failure))
        }
    }

    func testIncompleteFailedAndAdditionalTurnsCannotRecover() {
        let error = #"{"type":"error","message":"Stream failed."}"#
        let failed = #"{"type":"turn.failed","error":{"message":"Turn failed."}}"#
        let streams = [
            [Self.started, Self.message],
            [Self.started, Self.completed],
            [Self.message, Self.started, Self.completed],
            [Self.message, Self.completed],
            [Self.started, Self.started, Self.message, Self.completed],
            [Self.started, Self.message, Self.completed, Self.started],
            [Self.started, Self.message, Self.completed, Self.message],
            [Self.started, Self.message, Self.completed, Self.completed],
            [Self.started, Self.message, error, Self.completed],
            [Self.started, Self.message, failed, Self.completed],
            [Self.started, Self.message, Self.completed, error]
        ]
        for events in streams {
            let output = Self.stream(events)
            XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: Self.result(stdout: output))), output)
        }
    }

    func testLegacyOrEmptyFinalMessagesCannotReplaceProvenCompletedMessage() {
        let legacy = #"{"type":"agent_message","text":"Unproven replacement."}"#
        let empty = #"{"type":"item.completed","item":{"type":"agent_message","text":" \n "}}"#
        let missingText = #"{"type":"item.completed","item":{"type":"agent_message"}}"#
        let invalidItem = #"{"type":"item.completed","item":null}"#
        for record in [legacy, empty, missingText, invalidItem] {
            let output = Self.stream([Self.started, Self.message, record, Self.completed])
            XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: Self.result(stdout: output))), output)
        }
    }

    func testEveryRecordMustBeACompleteJSONObjectWithAType() {
        for record in ["not-json", "[]", "{}", #"{"type":3}"#, #"{"type":"item.completed""#] {
            let output = Self.stream([Self.started, record, Self.message, Self.completed])
            XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: Self.result(stdout: output))), output)
        }
    }

    func testMissingFinalNewlineAndPartialTrailingRecordsCannotRecover() {
        let complete = Self.stream([Self.thread, Self.started, Self.message, Self.completed])
        for output in [String(complete.dropLast()), String(complete.dropLast(2)), complete + "{", "", "\n \t\n"] {
            XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: Self.result(stdout: output))), output)
        }
    }

    func testOriginalBytesMustBeValidUTF8AndMatchTextPassedToSDK() {
        let complete = Self.stream([Self.thread, Self.started, Self.message, Self.completed])
        let invalidData = Data([0xFF, 0x0A]) + Data(complete.utf8)
        let invalidUTF8 = Self.result(stdout: complete, stdoutData: invalidData)
        XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: invalidUTF8)))
        let mismatchedText = Self.result(stdout: "different output", stdoutData: Data(complete.utf8))
        XCTAssertFalse(ReviewWorkerCodexCompletion.canRecover(Self.failure(result: mismatchedText)))
    }

    private static let thread = #"{"type":"thread.started","thread_id":"thread-1"}"#
    private static let started = #"{"type":"turn.started"}"#
    private static let message = #"{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"{\"findings\":[]}"}}"#
    private static let completed = #"{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}"#

    private static func stream(_ events: [String]) -> String {
        events.joined(separator: "\n") + "\n"
    }

    private static func result(
        stdout: String = stream([thread, started, message, completed]),
        stdoutData: Data? = nil,
        exitCode: Int32 = 0,
        stdoutWasTruncated: Bool = false,
        stderrWasTruncated: Bool = false
    ) -> ShellResult {
        ShellResult(stdout: stdout, stdoutData: stdoutData, stderr: "", exitCode: exitCode,
                    stdoutWasTruncated: stdoutWasTruncated, stderrWasTruncated: stderrWasTruncated)
    }

    private static func failure(
        result: ShellResult = result(),
        exitedNormally: Bool = true,
        inputCompleted: Bool = true,
        stdoutFailure: ShellOutputFailure? = .drainTimedOut,
        stderrFailure: ShellOutputFailure? = nil
    ) -> ShellIOFailure {
        ShellIOFailure(executable: "codex", result: result, exitedNormally: exitedNormally, inputCompleted: inputCompleted,
                       stdoutFailure: stdoutFailure, stderrFailure: stderrFailure)
    }
}
