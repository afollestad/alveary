import Foundation

/// The four services demo mode replaces.
///
/// Each accessor answers `nil` outside demo mode, so its registration in `AppComponent` reads as
/// `demoX ?? RealX(...)` and constructs the real service lazily. Keeping the branches here rather
/// than inline avoids pushing `AppComponent.swift` past SwiftLint's `file_length` threshold, and
/// keeps every `#if DEBUG` in the DI layer in one place.
///
/// The branch is on `storageProfile.isDemo`, never `AppRuntimeProfile.current`: the storage
/// profile is what the rest of the app actually runs against, so services and storage cannot
/// disagree.
@MainActor
extension AppComponent {
    var demoGitService: GitService? {
        #if DEBUG
        guard storageProfile.isDemo else {
            return nil
        }
        return DemoGitService(wrapping: CLIGitService(shell: shellRunner))
        #else
        return nil
        #endif
    }

    var demoSkillsService: SkillsService? {
        #if DEBUG
        guard storageProfile.isDemo else {
            return nil
        }
        return DemoSkillsService()
        #else
        return nil
        #endif
    }

    var demoMCPService: MCPService? {
        #if DEBUG
        guard storageProfile.isDemo else {
            return nil
        }
        return DemoMCPService()
        #else
        return nil
        #endif
    }

    var demoPullRequestsService: (any PullRequestsService)? {
        #if DEBUG
        guard storageProfile.isDemo else {
            return nil
        }
        return DemoPullRequestsService()
        #else
        return nil
        #endif
    }
}
