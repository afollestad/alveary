@preconcurrency import AppKit
import Foundation

@MainActor
protocol TerminalSessionControlling: AnyObject {
    var view: NSView { get }

    func start()
    func terminate()
    func requestFocus()
    func reapplyTheme()
}

@MainActor
protocol TerminalSessionControllerFactory: AnyObject {
    func makeController(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) -> any TerminalSessionControlling
}

@MainActor
protocol TerminalSessionControllerDelegate: AnyObject {
    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didTerminateSession id: UUID,
        exitCode: Int32?
    )

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didCompleteProjectAction id: UUID,
        exitCode: Int32
    )

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateTitle title: String,
        forSession id: UUID
    )

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateCurrentDirectory currentDirectory: String,
        forSession id: UUID
    )
}
