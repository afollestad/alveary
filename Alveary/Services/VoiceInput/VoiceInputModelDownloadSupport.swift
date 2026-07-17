import CryptoKit
import Foundation

enum VoiceInputModelArtifactIntegrity {
    static func contentHash(of url: URL, artifact: VoiceInputModelArtifact) throws -> Bool {
        let actualHash: String
        switch artifact.digestType {
        case .sha256:
            var hasher = SHA256()
            try readFileChunks(at: url) { hasher.update(data: $0) }
            actualHash = hexString(hasher.finalize())
        case .gitBlobSHA1:
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(artifact.size)\0".utf8))
            try readFileChunks(at: url) { hasher.update(data: $0) }
            actualHash = hexString(hasher.finalize())
        }
        return actualHash == artifact.digest
    }

    private static func readFileChunks(at url: URL, consume: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            consume(chunk)
        }
    }

    private static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum VoiceInputModelArtifactInventory {
    static func expectedDirectoryPaths(for artifacts: [VoiceInputModelArtifact]) -> Set<String> {
        var result = Set<String>()
        for artifact in artifacts {
            let components = artifact.path.split(separator: "/")
            guard components.count > 1 else { continue }
            for componentCount in 1..<components.count {
                result.insert(components.prefix(componentCount).map(String.init).joined(separator: "/"))
            }
        }
        return result
    }
}

enum VoiceInputModelFileError {
    static func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch where isNoSuchFile(error) {
            return
        }
    }

    static func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == POSIXErrorCode.ENOENT.rawValue {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNoSuchFile(underlying)
        }
        return false
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.cancelled.rawValue {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.userCancelled.rawValue {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }

    static func cacheError(for error: Error) -> VoiceInputServiceError {
        if isDiskFull(error) {
            return .diskFull
        }
        return .modelCache(error.localizedDescription)
    }

    static func isLocalFileSystemError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           localFileSystemPOSIXCodes.contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isLocalFileSystemError(underlying)
        }
        return false
    }

    static func isDiskFull(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           diskFullPOSIXCodes.contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isDiskFull(underlying)
        }
        return false
    }

    private static let diskFullPOSIXCodes = Set([
        POSIXErrorCode.EDQUOT,
        POSIXErrorCode.ENOSPC
    ].map { Int($0.rawValue) })

    private static let localFileSystemPOSIXCodes = Set([
        POSIXErrorCode.EACCES,
        POSIXErrorCode.EBADF,
        POSIXErrorCode.EDQUOT,
        POSIXErrorCode.EEXIST,
        POSIXErrorCode.EFBIG,
        POSIXErrorCode.EIO,
        POSIXErrorCode.EISDIR,
        POSIXErrorCode.ELOOP,
        POSIXErrorCode.EMFILE,
        POSIXErrorCode.ENAMETOOLONG,
        POSIXErrorCode.ENFILE,
        POSIXErrorCode.ENOENT,
        POSIXErrorCode.ENOSPC,
        POSIXErrorCode.ENOTDIR,
        POSIXErrorCode.ENOTEMPTY,
        POSIXErrorCode.EPERM,
        POSIXErrorCode.EROFS
    ].map { Int($0.rawValue) })
}

final class CoalescingVoiceInputDownloadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (Double) -> Void
    private var lastFraction = 0.0
    private var lastWholePercentage = -1
    private var lastReportUptime = 0.0

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func report(_ fraction: Double) {
        let next = lock.withLock { () -> Double? in
            let clamped = min(1, max(lastFraction, fraction))
            lastFraction = clamped
            let wholePercentage = Int(clamped * 100)
            let now = ProcessInfo.processInfo.systemUptime
            guard wholePercentage > lastWholePercentage || now - lastReportUptime >= 0.1 else {
                return nil
            }
            lastWholePercentage = wholePercentage
            lastReportUptime = now
            return clamped
        }
        if let next {
            progress(next)
        }
    }
}
