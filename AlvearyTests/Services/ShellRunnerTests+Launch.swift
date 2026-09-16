import Darwin
import Foundation
import XCTest

@testable import Alveary

extension ShellRunnerTests {
    func testBadDescriptorDuringLaunchIdentifiesExecutableWithoutExposingArguments() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'private-review-body'"]
        // An impossible descriptor reproduces POSIX EBADF without closing a descriptor another thread could reuse.
        process.standardInput = FileHandle(fileDescriptor: .max, closeOnDealloc: false)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try DefaultShellRunner.launch(process, executable: "/bin/sh")
            XCTFail("Expected failure before the command launches")
        } catch let ShellError.launchFailed(executable, domain, code, reason) {
            XCTAssertEqual(executable, "/bin/sh")
            XCTAssertEqual(domain, NSPOSIXErrorDomain)
            XCTAssertEqual(code, Int(EBADF))
            XCTAssertFalse(reason.isEmpty)
            let error = ShellError.launchFailed(executable: executable, domain: domain, code: code, reason: reason)
            for diagnostic in [error.localizedDescription, String(describing: error), String(reflecting: error)] {
                XCTAssertTrue(diagnostic.contains("Could not launch /bin/sh"))
                XCTAssertTrue(diagnostic.contains("NSPOSIXErrorDomain, code 9"))
                XCTAssertFalse(diagnostic.contains("private-review-body"))
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(process.isRunning)
    }

    func testMissingExecutableIsReportedAsLaunchFailureThroughRunner() async {
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent("missing-cli-\(UUID().uuidString)").path
        do {
            _ = try await DefaultShellRunner().run(executable: executable, args: ["private-review-body"], standardInput: .nullDevice)
            XCTFail("Expected a launch failure")
        } catch let ShellError.launchFailed(failedExecutable, domain, _, reason) {
            XCTAssertEqual(failedExecutable, executable)
            XCTAssertFalse(domain.isEmpty)
            XCTAssertFalse(reason.isEmpty)
            XCTAssertFalse(reason.contains("private-review-body"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
