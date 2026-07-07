import Foundation

protocol AppVersionProviding: Sendable {
    var currentVersionString: String? { get }
    var currentVersion: AppUpdateVersion? { get }
}

struct BundleAppVersionProvider: AppVersionProviding, @unchecked Sendable {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var currentVersionString: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var currentVersion: AppUpdateVersion? {
        currentVersionString.flatMap(AppUpdateVersion.init(string:))
    }
}
