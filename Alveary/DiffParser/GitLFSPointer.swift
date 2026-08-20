import Foundation

/// A Git LFS pointer as it appears inline in a diff.
///
/// LFS-tracked files reach the app as *text* diffs of the three-line pointer, never as
/// `Binary files … differ`, so `DiffFile.isBinary` is `false` for them and the raster-preview gate
/// must read hunk lines rather than that flag. The pointer also carries the real byte size, which is
/// what lets a caller apply a size policy without spending a network round trip to discover it.
struct GitLFSPointer: Sendable, Equatable, Hashable {
    /// The object's SHA-256, lowercase hex. Content-addressed, so it identifies the bytes
    /// independently of any ref — which is why an LFS side needs no commit SHA to be fetched.
    let oid: String
    let byteSize: Int

    /// The only `version` line Git LFS writes for the v1 spec. Matched exactly rather than by
    /// prefix so a file that merely *mentions* the URL cannot be mistaken for a pointer.
    private static let versionLine = "version https://git-lfs.github.com/spec/v1"
    private static let oidPrefix = "oid sha256:"
    private static let sizePrefix = "size "
    private static let oidHexLength = 64
    /// A pointer file is three lines, so even a modified one shows only a handful. Rejecting on the
    /// count first is what keeps `pointers(in:)` off the hot path — every file in a pull request
    /// diff is asked, and a large source file would otherwise have all its lines copied twice only
    /// for the very first one to disqualify it.
    private static let maximumPointerDiffLines = 12

    /// Parses the pointer's own text. Deliberately strict: the version line must come first, `oid`
    /// and `size` must each appear exactly once, and no other non-empty line may be present. A
    /// looser grammar would turn documentation quoting the spec into a fake image row.
    static func parse(lines: [String]) -> GitLFSPointer? {
        var oid: String?
        var byteSize: Int?
        var sawVersion = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }

            if !sawVersion {
                guard line == versionLine else {
                    return nil
                }
                sawVersion = true
                continue
            }

            if line.hasPrefix(oidPrefix) {
                guard oid == nil, let parsed = parseOID(line: line) else {
                    return nil
                }
                oid = parsed
            } else if line.hasPrefix(sizePrefix) {
                guard byteSize == nil, let parsed = parseSize(line: line) else {
                    return nil
                }
                byteSize = parsed
            } else {
                // Any other content means this is not a pointer file.
                return nil
            }
        }

        guard sawVersion, let oid, let byteSize else {
            return nil
        }
        return GitLFSPointer(oid: oid, byteSize: byteSize)
    }

    private static func parseOID(line: String) -> String? {
        let hex = String(line.dropFirst(oidPrefix.count))
        guard hex.count == oidHexLength, hex.allSatisfy(\.isHexDigitLowercase) else {
            return nil
        }
        return hex
    }

    private static func parseSize(line: String) -> Int? {
        let digits = String(line.dropFirst(sizePrefix.count))
        guard !digits.isEmpty,
              digits.allSatisfy(\.isNumber),
              let parsed = Int(digits),
              parsed >= 0 else {
            return nil
        }
        return parsed
    }

    /// The pointers on each side of a file diff, reconstructed from the hunk lines.
    ///
    /// A pointer file is small enough that Git never splits it, so the old side is the context plus
    /// deleted lines and the new side the context plus added lines. Either side is nil when that
    /// side is absent (an add or a delete) or when the reconstructed text is not a valid pointer.
    static func pointers(in file: DiffFile) -> (old: GitLFSPointer?, new: GitLFSPointer?) {
        guard !file.isBinary, !file.hunks.isEmpty else {
            return (nil, nil)
        }

        let lineCount = file.hunks.reduce(0) { $0 + $1.lines.count }
        guard lineCount <= maximumPointerDiffLines else {
            return (nil, nil)
        }

        var oldLines: [String] = []
        var newLines: [String] = []
        for hunk in file.hunks {
            for line in hunk.lines {
                switch line.type {
                case .context:
                    oldLines.append(line.content)
                    newLines.append(line.content)
                case .deleted:
                    oldLines.append(line.content)
                case .added:
                    newLines.append(line.content)
                }
            }
        }

        return (parse(lines: oldLines), parse(lines: newLines))
    }
}

private extension Character {
    /// Git LFS writes the digest lowercase; accepting uppercase would let two spellings of one
    /// object produce two cache entries.
    var isHexDigitLowercase: Bool {
        isHexDigit && !isUppercase
    }
}
