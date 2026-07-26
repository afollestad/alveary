import AppKit
import Foundation

/// The lifecycle notifications these tests hand to `AppDelegate`.
///
/// Written as explicitly typed helpers rather than repeating
/// `Notification(name: NSApplication.didFinishLaunchingNotification)` at each call site: CI
/// measured one of those inline expressions at 3941ms to type-check, against a 3000ms budget.
/// A call with a declared return type gives the solver a fixed target instead of re-resolving
/// the initializer and the static member together seventeen times.
func appDelegateDidFinishLaunchingNotification() -> Notification {
    Notification(name: NSApplication.didFinishLaunchingNotification)
}

func appDelegateWillTerminateNotification() -> Notification {
    Notification(name: NSApplication.willTerminateNotification)
}
