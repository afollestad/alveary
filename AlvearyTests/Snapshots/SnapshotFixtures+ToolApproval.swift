import Foundation

@testable import Alveary

extension SnapshotTests {
    var sampleWriteApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-write",
            toolName: "Write",
            toolInput: #"{"file_path":"\#(NSHomeDirectory())/Development/alveary/test_parallel.txt","content":"test"}"#
        )
    }
}
