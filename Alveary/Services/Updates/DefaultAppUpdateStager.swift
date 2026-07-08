import Foundation

struct DefaultAppUpdateStager: AppUpdateStaging, @unchecked Sendable {
    private let updatesDirectory: URL
    private let shellRunner: any ShellRunner
    private let fileManager: FileManager
    private let bundle: Bundle
    private let now: @Sendable () -> Date

    init(
        updatesDirectory: URL,
        shellRunner: any ShellRunner,
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.updatesDirectory = updatesDirectory
        self.shellRunner = shellRunner
        self.fileManager = fileManager
        self.bundle = bundle
        self.now = now
    }

    func stageDownloadedUpdate(
        release: AppUpdateRelease,
        downloadedZIPURL: URL
    ) async throws -> StagedAppUpdate {
        try validateCurrentInstallLocation()
        try fileManager.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true
        )

        let workingDirectory = updatesDirectory
            .appendingPathComponent("Working", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extractedDirectory = workingDirectory
            .appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(
            at: extractedDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: workingDirectory)
            try? fileManager.removeItem(at: downloadedZIPURL)
        }

        try await runRequired(
            executable: "/usr/bin/ditto",
            args: ["-x", "-k", downloadedZIPURL.path, extractedDirectory.path],
            failureMessage: "Could not extract the update archive."
        )

        let extractedAppURL = extractedDirectory.appendingPathComponent("Alveary.app", isDirectory: true)
        try await validateExtractedApp(extractedAppURL, release: release)

        let stagedDirectory = updatesDirectory
            .appendingPathComponent("Staged", isDirectory: true)
            .appendingPathComponent(release.tagName.sanitizedForPathComponent, isDirectory: true)
        let stagedAppURL = stagedDirectory.appendingPathComponent("Alveary.app", isDirectory: true)
        try? fileManager.removeItem(at: stagedDirectory)
        try fileManager.createDirectory(
            at: stagedDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: extractedAppURL, to: stagedAppURL)

        let stagedUpdate = StagedAppUpdate(
            release: release,
            appBundleURL: stagedAppURL,
            metadataURL: metadataURL,
            stagedAt: now()
        )
        try writeMetadata(for: stagedUpdate)
        return stagedUpdate
    }

    func loadValidatedStagedUpdate() async throws -> StagedAppUpdate? {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        do {
            let metadata = try JSONDecoder.appUpdateMetadata.decode(
                AppUpdateStagedMetadata.self,
                from: try Data(contentsOf: metadataURL)
            )
            let stagedUpdate = try metadata.stagedUpdate(metadataURL: metadataURL)
            try validateCurrentInstallLocation()
            try await validateExtractedApp(stagedUpdate.appBundleURL, release: stagedUpdate.release)
            return stagedUpdate
        } catch {
            try? fileManager.removeItem(at: metadataURL)
            throw error
        }
    }

    private var metadataURL: URL {
        updatesDirectory.appendingPathComponent("staged-update.json")
    }
}

private extension DefaultAppUpdateStager {
    func validateCurrentInstallLocation() throws {
        let currentBundleURL = bundle.bundleURL.standardizedFileURL
        guard currentBundleURL.pathExtension == "app" else {
            throw AppUpdateFailure(message: "Alveary is not running from an app bundle.")
        }
        guard !currentBundleURL.path.contains("/AppTranslocation/") else {
            throw AppUpdateFailure(message: "Move Alveary out of the translocated disk image before installing updates.")
        }
        guard !currentBundleURL.path.isDevelopmentBuildPath else {
            throw AppUpdateFailure(message: "Updates cannot be installed over a development build.")
        }

        let parentDirectory = currentBundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdateFailure(message: "Alveary's install location is not writable.")
        }
    }

    func validateExtractedApp(_ appURL: URL, release: AppUpdateRelease) async throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              appURL.lastPathComponent == "Alveary.app" else {
            throw AppUpdateFailure(message: "The update archive did not contain Alveary.app at the top level.")
        }
        guard let stagedBundle = Bundle(url: appURL),
              stagedBundle.bundleIdentifier == bundle.bundleIdentifier else {
            throw AppUpdateFailure(message: "The staged app bundle identifier does not match Alveary.")
        }
        let stagedVersionString = stagedBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let stagedVersion = stagedVersionString.flatMap(AppUpdateVersion.init(string:)),
              stagedVersion == release.version else {
            throw AppUpdateFailure(message: "The staged app version does not match \(release.tagName).")
        }
        if let currentVersionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let currentVersion = AppUpdateVersion(string: currentVersionString),
           stagedVersion <= currentVersion {
            throw AppUpdateFailure(message: "The staged update is not newer than this Alveary build.")
        }

        try await verifyCodeSignature(appURL)
        try await assessGatekeeper(appURL)
        try await verifySigningMatchesCurrentBundle(stagedAppURL: appURL)
    }

    func verifyCodeSignature(_ appURL: URL) async throws {
        try await runRequired(
            executable: "/usr/bin/codesign",
            args: ["--verify", "--deep", "--strict", "--verbose=2", appURL.path],
            failureMessage: "The staged app's code signature is invalid."
        )
    }

    func assessGatekeeper(_ appURL: URL) async throws {
        try await runRequired(
            executable: "/usr/sbin/spctl",
            args: ["--assess", "--type", "execute", "--verbose=2", appURL.path],
            failureMessage: "Gatekeeper rejected the staged app."
        )
    }

    func verifySigningMatchesCurrentBundle(stagedAppURL: URL) async throws {
        let currentSignature = try await signatureDetails(for: bundle.bundleURL)
        let stagedSignature = try await signatureDetails(for: stagedAppURL)

        guard let currentTeamIdentifier = currentSignature.teamIdentifier,
              let stagedTeamIdentifier = stagedSignature.teamIdentifier,
              currentTeamIdentifier == stagedTeamIdentifier else {
            throw AppUpdateFailure(message: "The staged app is not signed by the same team as the running app.")
        }
        guard !currentSignature.authorities.isEmpty,
              currentSignature.authorities == stagedSignature.authorities else {
            throw AppUpdateFailure(message: "The staged app signing identity does not match the running app.")
        }
    }

    func signatureDetails(for appURL: URL) async throws -> AppUpdateSignatureDetails {
        let result = try await shellRunner.run(
            executable: "/usr/bin/codesign",
            args: ["-dv", "--verbose=4", appURL.path],
            timeout: .seconds(30),
            stdoutLimitBytes: 64 * 1024,
            stderrLimitBytes: 64 * 1024
        )
        guard result.succeeded else {
            throw AppUpdateFailure(message: "Could not read the app signing identity.")
        }
        return AppUpdateSignatureDetails(output: result.stderr)
    }

    func runRequired(
        executable: String,
        args: [String],
        failureMessage: String
    ) async throws {
        let result = try await shellRunner.run(
            executable: executable,
            args: args,
            timeout: .seconds(120),
            stdoutLimitBytes: 64 * 1024,
            stderrLimitBytes: 64 * 1024
        )
        guard result.succeeded else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateFailure(message: detail.isEmpty ? failureMessage : "\(failureMessage) \(detail)")
        }
    }

    func writeMetadata(for stagedUpdate: StagedAppUpdate) throws {
        let metadata = AppUpdateStagedMetadata(stagedUpdate: stagedUpdate)
        try fileManager.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder.appUpdateMetadata
            .encode(metadata)
            .write(to: metadataURL, options: [.atomic])
    }
}

private struct AppUpdateSignatureDetails: Equatable {
    let teamIdentifier: String?
    let authorities: [String]

    init(output: String) {
        var teamIdentifier: String?
        var authorities: [String] = []

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("TeamIdentifier=") {
                teamIdentifier = String(line.dropFirst("TeamIdentifier=".count))
            } else if line.hasPrefix("Authority=") {
                authorities.append(String(line.dropFirst("Authority=".count)))
            }
        }

        self.teamIdentifier = teamIdentifier
        self.authorities = authorities
    }
}

private struct AppUpdateStagedMetadata: Codable {
    let tagName: String
    let version: String
    let changelogMarkdown: String
    let htmlURL: URL
    let repositoryHTMLURL: URL
    let assetName: String
    let assetAPIURL: URL?
    let assetDownloadURL: URL
    let assetSize: Int?
    let assetDigest: String
    let appBundleURL: URL
    let stagedAt: Date

    init(stagedUpdate: StagedAppUpdate) {
        tagName = stagedUpdate.release.tagName
        version = stagedUpdate.release.version.description
        changelogMarkdown = stagedUpdate.release.changelogMarkdown
        htmlURL = stagedUpdate.release.htmlURL
        repositoryHTMLURL = stagedUpdate.release.repositoryHTMLURL
        assetName = stagedUpdate.release.asset.name
        assetAPIURL = stagedUpdate.release.asset.apiURL
        assetDownloadURL = stagedUpdate.release.asset.downloadURL
        assetSize = stagedUpdate.release.asset.size
        assetDigest = stagedUpdate.release.asset.digest.gitHubDigest
        appBundleURL = stagedUpdate.appBundleURL
        stagedAt = stagedUpdate.stagedAt
    }

    func stagedUpdate(metadataURL: URL) throws -> StagedAppUpdate {
        guard let parsedVersion = AppUpdateVersion(string: version) else {
            throw AppUpdateFailure(message: "The staged update metadata has an invalid version.")
        }
        guard let parsedAssetDigest = AppUpdateReleaseAssetDigest(gitHubDigest: assetDigest) else {
            throw AppUpdateFailure(message: "The staged update metadata has an invalid asset digest.")
        }
        return StagedAppUpdate(
            release: AppUpdateRelease(
                tagName: tagName,
                version: parsedVersion,
                changelogMarkdown: changelogMarkdown,
                htmlURL: htmlURL,
                repositoryHTMLURL: repositoryHTMLURL,
                asset: AppUpdateReleaseAsset(
                    name: assetName,
                    apiURL: assetAPIURL ?? assetDownloadURL,
                    downloadURL: assetDownloadURL,
                    size: assetSize,
                    digest: parsedAssetDigest
                )
            ),
            appBundleURL: appBundleURL,
            metadataURL: metadataURL,
            stagedAt: stagedAt
        )
    }
}

private extension JSONEncoder {
    static var appUpdateMetadata: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var appUpdateMetadata: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var sanitizedForPathComponent: String {
        components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    var isDevelopmentBuildPath: Bool {
        contains("/DerivedData/")
            || contains("/Build/Products/")
            || contains("/.build/")
    }
}
