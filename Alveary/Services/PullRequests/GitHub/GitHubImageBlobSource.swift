import Foundation

/// A pull request image addressed on GitHub rather than in a checkout.
struct GitHubImageBlobSource: Sendable, Hashable {
    /// Which transport serves this blob's bytes.
    ///
    /// The two hosts are complementary, never interchangeable: `raw.githubusercontent.com` returns
    /// the *pointer text* for an LFS-tracked path, and `media.githubusercontent.com` 404s for a path
    /// that is not LFS-tracked. The choice is read off the diff — pointer lines present means
    /// `.lfs` — so it is never a guess and never needs a probe request.
    enum Storage: Sendable, Hashable {
        /// An ordinary Git blob, addressed by the commit it appears in.
        case blob(ref: String)
        /// An LFS object, addressed by its own content hash. Needs no ref, which is why the "before"
        /// side of a modified image is exact without resolving the pull request's merge base.
        case lfs(oid: String, byteSize: Int)
    }

    let owner: String
    let repo: String
    let path: String
    let storage: Storage
}
