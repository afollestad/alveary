import CoreGraphics

/// The last transcript content width this process laid out, so a freshly mounted transcript can
/// measure at the right width on its very first pass.
///
/// `ChatTranscriptView.transcriptContentWidth` can only be filled by `.onGeometryChange`, which runs
/// after the first layout. Starting it at `0` makes `adaptiveTranscriptBubbleMaxWidth` return
/// `.infinity`, and `bubbleMaxWidth` is part of `AppKitTranscriptScrollViewRepresentable`'s
/// `ContentSignature` — so the first pass builds and exactly measures every row at a width the geometry
/// callback immediately invalidates, and the whole transcript is remeasured. Both the markdown document
/// cache and the prepared-layout cache key on width, so nothing carries over and the first pass's cold
/// markdown parse is pure waste. Seeding from here makes the second pass's signature match, and the
/// coordinator skips it.
///
/// One unkeyed value is enough: every conversation in a window shares one transcript width. A window
/// resize or right-pane change simply leaves a stale seed that the next geometry callback corrects, which
/// is exactly today's behavior. An empty cache — the first transcript of a launch, or a snapshot host that
/// never lays out — also falls back to today's behavior, so this can never open the surface empty.
@MainActor
enum TranscriptContentWidthCache {
    private static var width: CGFloat?

    static var lastKnownWidth: CGFloat? {
        width
    }

    static func store(_ width: CGFloat) {
        guard width > 0 else {
            return
        }
        self.width = width
    }

    #if DEBUG
    static func removeAll() {
        width = nil
    }
    #endif
}
