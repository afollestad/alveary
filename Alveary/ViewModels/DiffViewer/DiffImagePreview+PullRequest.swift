import Foundation

/// Builds image previews for a pull request diff, whose bytes live on GitHub rather than in a
/// checkout. Kept apart from the checkout-backed builders so the two sets of rules — which side maps
/// to which ref, and which storage serves it — stay readable side by side.
extension DiffImagePreviewSupport {
    /// One entry per previewable file, keyed the way the flattened row builder keys its files.
    static func pullRequestPreviews(
        for files: [DiffFile],
        owner: String,
        repo: String,
        headRef: String?,
        baseRef: String?
    ) -> [String: DiffImagePreview] {
        var previews: [String: DiffImagePreview] = [:]
        for (fileIndex, file) in files.enumerated() {
            guard let preview = pullRequestPreview(
                for: file,
                owner: owner,
                repo: repo,
                headRef: headRef,
                baseRef: baseRef
            ) else {
                continue
            }
            previews[fileID(for: file, fileIndex: fileIndex)] = preview
        }
        return previews
    }

    static func pullRequestPreview(
        for file: DiffFile,
        owner: String,
        repo: String,
        headRef: String?,
        baseRef: String?
    ) -> DiffImagePreview? {
        // An LFS file is a *text* diff of pointer lines, so `isBinary` is false for it and the two
        // detections have to run independently rather than as an if/else on that flag.
        let pointers = GitLFSPointer.pointers(in: file)

        let oldVersion = file.oldPath.flatMap { path in
            remoteVersion(
                owner: owner,
                repo: repo,
                isBinary: file.isBinary,
                side: RemoteImageSide(path: path, side: .old, pointer: pointers.old, ref: baseRef)
            )
        }
        let newVersion = file.newPath.flatMap { path in
            remoteVersion(
                owner: owner,
                repo: repo,
                isBinary: file.isBinary,
                side: RemoteImageSide(path: path, side: .new, pointer: pointers.new, ref: headRef)
            )
        }

        guard oldVersion != nil || newVersion != nil else {
            return nil
        }
        return DiffImagePreview(old: oldVersion, new: newVersion)
    }

    private static func remoteVersion(
        owner: String,
        repo: String,
        isBinary: Bool,
        side: RemoteImageSide
    ) -> DiffImageVersion? {
        guard canPreviewImage(path: side.path) else {
            return nil
        }

        let storage: GitHubImageBlobSource.Storage
        let identityPrefix: String
        let byteSize: Int?

        if let pointer = side.pointer {
            storage = .lfs(oid: pointer.oid, byteSize: pointer.byteSize)
            // Content-addressed, so the oid alone pins these bytes for the disk cache.
            identityPrefix = "lfs-\(pointer.oid)"
            byteSize = pointer.byteSize
        } else if isBinary, let ref = side.ref {
            storage = .blob(ref: ref)
            identityPrefix = ref
            byteSize = nil
        } else {
            return nil
        }

        return DiffImageVersion(
            source: .gitHub(
                GitHubImageBlobSource(owner: owner, repo: repo, path: side.path, storage: storage)
            ),
            side: side.side,
            identityPrefix: identityPrefix,
            fileIdentity: side.path,
            fileExtension: imageExtension(for: side.path),
            // Both remote storages are immutable — content- or commit-addressed — so the disk cache
            // can be probed by name without first reading the bytes to hash them.
            needsContentHash: false,
            byteSize: byteSize
        )
    }
}

/// One side of a file diff, bundled so the version builder reads as a single decision rather than a
/// long parameter list that pairs each side with its own ref and pointer.
private struct RemoteImageSide {
    let path: String
    let side: DiffImageVersion.Side
    let pointer: GitLFSPointer?
    /// The commit that side is read from. Nil leaves an ordinary binary image unrenderable, which is
    /// why a pull request whose detail has not loaded yet still shows its LFS images (those are
    /// addressed by content hash and need no ref) but not its plain ones.
    let ref: String?
}
