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
            XCTAssertEqual(ReviewWorkerCodexCompletion.assess(failure), .recoverable)
        }
    }

    func testCompletedTurnAllowsBlankLinesCRLFAndEarlierCompletedItems() {
        let reasoning = #"{"type":"item.completed","item":{"type":"reasoning","text":"Checking the diff."}}"#
        let output = Self.stream([Self.thread, Self.started, reasoning, Self.message, Self.message, Self.completed])
        let variants = [output, "\n \t\n" + output + "\n", output.replacingOccurrences(of: "\n", with: "\r\n")]
        for variant in variants {
            XCTAssertEqual(ReviewWorkerCodexCompletion.assess(Self.failure(result: Self.result(stdout: variant))), .recoverable)
        }
    }

    func testProcessAndCaptureFailuresCannotRecoverDespiteCompletedTurn() {
        let cases: [(ShellIOFailure, ReviewWorkerCodexCompletion.RejectionReason)] = [
            (Self.failure(exitedNormally: false), .unsuccessfulExit),
            (Self.failure(inputCompleted: false), .incompleteInput),
            (Self.failure(result: Self.result(exitCode: 7)), .unsuccessfulExit),
            (Self.failure(result: Self.result(stdoutWasTruncated: true)), .truncatedOutput),
            (Self.failure(result: Self.result(stderrWasTruncated: true)), .truncatedOutput),
            (Self.failure(stdoutFailure: nil), .ineligibleIOFailure),
            (Self.failure(stdoutFailure: .readFailed(5)), .ineligibleIOFailure),
            (Self.failure(stderrFailure: .readFailed(5)), .ineligibleIOFailure),
            (Self.failure(stdoutFailure: .readFailed(5), stderrFailure: .drainTimedOut), .ineligibleIOFailure)
        ]
        for (failure, reason) in cases {
            XCTAssertEqual(ReviewWorkerCodexCompletion.assess(failure), .rejected(reason))
        }
    }

    func testIncompleteFailedAndAdditionalTurnsCannotRecover() {
        let error = #"{"type":"error","message":"Stream failed."}"#
        let failed = #"{"type":"turn.failed","error":{"message":"Turn failed."}}"#
        let cases: [([String], ReviewWorkerCodexCompletion.Assessment)] = [
            ([Self.started, Self.message], .rejected(.missingCompletion)),
            ([Self.started, Self.completed], .rejected(.missingFinalAnswer, recordNumber: 2)),
            ([Self.message, Self.started, Self.completed], .rejected(.invalidTurnSequence, recordNumber: 1)),
            ([Self.message, Self.completed], .rejected(.invalidTurnSequence, recordNumber: 1)),
            ([Self.started, Self.started, Self.message, Self.completed], .rejected(.invalidTurnSequence, recordNumber: 2)),
            ([Self.started, Self.message, Self.completed, Self.started], .rejected(.eventsAfterCompletion, recordNumber: 4)),
            ([Self.started, Self.message, Self.completed, Self.message], .rejected(.eventsAfterCompletion, recordNumber: 4)),
            ([Self.started, Self.message, Self.completed, Self.completed], .rejected(.eventsAfterCompletion, recordNumber: 4)),
            ([Self.started, Self.message, error, Self.completed], .rejected(.failedTurn, recordNumber: 3)),
            ([Self.started, Self.message, failed, Self.completed], .rejected(.failedTurn, recordNumber: 3)),
            ([Self.started, Self.message, Self.completed, error], .rejected(.eventsAfterCompletion, recordNumber: 4))
        ]
        for (events, assessment) in cases {
            let output = Self.stream(events)
            XCTAssertEqual(ReviewWorkerCodexCompletion.assess(Self.failure(result: Self.result(stdout: output))), assessment)
        }
    }

    func testLegacyOrEmptyFinalMessagesCannotReplaceProvenCompletedMessage() {
        let legacy = #"{"type":"agent_message","text":"Unproven replacement."}"#
        let empty = #"{"type":"item.completed","item":{"type":"agent_message","text":" \n "}}"#
        let missingText = #"{"type":"item.completed","item":{"type":"agent_message"}}"#
        let invalidItem = #"{"type":"item.completed","item":null}"#
        let cases: [(String, ReviewWorkerCodexCompletion.RejectionReason)] = [
            (legacy, .legacyMessage), (empty, .missingFinalAnswer), (missingText, .missingFinalAnswer), (invalidItem, .invalidItem)
        ]
        for (record, reason) in cases {
            let output = Self.stream([Self.started, Self.message, record, Self.completed])
            let assessment = ReviewWorkerCodexCompletion.assess(Self.failure(result: Self.result(stdout: output)))
            XCTAssertEqual(assessment, .rejected(reason, recordNumber: 3))
        }
    }

    func testEveryRecordMustBeACompleteJSONObjectWithAType() {
        for record in ["not-json", "[]", "{}", #"{"type":3}"#, #"{"type":"item.completed""#] {
            let output = Self.stream(["", Self.started, " \t", record, Self.message, Self.completed])
            let assessment = ReviewWorkerCodexCompletion.assess(Self.failure(result: Self.result(stdout: output)))
            XCTAssertEqual(assessment, .rejected(.invalidEvent, recordNumber: 2))
        }
    }

    func testMissingFinalNewlineAndPartialTrailingRecordsCannotRecover() {
        let complete = Self.stream([Self.thread, Self.started, Self.message, Self.completed])
        for output in [String(complete.dropLast()), String(complete.dropLast(2)), complete + "{", ""] {
            let assessment = ReviewWorkerCodexCompletion.assess(Self.failure(result: Self.result(stdout: output)))
            XCTAssertEqual(assessment, .rejected(.missingFinalNewline))
        }
        let blank = Self.failure(result: Self.result(stdout: "\n \t\n"))
        XCTAssertEqual(ReviewWorkerCodexCompletion.assess(blank), .rejected(.missingCompletion))
    }

    func testOriginalBytesMustBeValidUTF8AndMatchTextPassedToSDK() {
        let complete = Self.stream([Self.thread, Self.started, Self.message, Self.completed])
        let invalidData = Data([0xFF, 0x0A]) + Data(complete.utf8)
        let invalidUTF8 = Self.result(stdout: complete, stdoutData: invalidData)
        XCTAssertEqual(ReviewWorkerCodexCompletion.assess(Self.failure(result: invalidUTF8)), .rejected(.invalidUTF8))
        let mismatchedText = Self.result(stdout: "different output", stdoutData: Data(complete.utf8))
        XCTAssertEqual(ReviewWorkerCodexCompletion.assess(Self.failure(result: mismatchedText)), .rejected(.inconsistentCapture))
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
