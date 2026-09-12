import Foundation

/// Definition edits replace this snapshot explicitly; claims and recovered runs consume it unchanged.
extension ScheduledTask {
    var workspaceSnapshot: WorkspaceSnapshot? {
        get { WorkspaceSnapshot.decode(workspaceSnapshotJSON) }
        set { workspaceSnapshotJSON = newValue?.encoded }
    }
}

extension ScheduledTaskRun {
    var workspaceSnapshot: WorkspaceSnapshot? {
        get { WorkspaceSnapshot.decode(workspaceSnapshotJSON) }
        set { workspaceSnapshotJSON = newValue?.encoded }
    }
}
