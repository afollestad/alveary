@preconcurrency import AppKit

extension AppKitTextView {
    func chipLeadingInset(
        for _: NSRange,
        layoutManager _: NSLayoutManager,
        textContainer _: NSTextContainer,
        desiredInset _: CGFloat
    ) -> CGFloat {
        0
    }

    func chipTrailingInset(
        for _: NSRange,
        layoutManager _: NSLayoutManager,
        textContainer _: NSTextContainer,
        desiredInset _: CGFloat
    ) -> CGFloat {
        0
    }
}
