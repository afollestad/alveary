## Shared View Components

These rules cover shared UI components under `Alveary/Views/Components/`.

## AppTextEditor And AppKitTextView

- Keep the placeholder drawn inside `AppKitTextView` instead of reintroducing a SwiftUI overlay so it shares the real `NSTextView` insets and caret positioning.
- Selection-change callbacks for `AppKitTextView` must not synchronously trigger layout-dependent restyling such as chip rect calculation or `NSLayoutManager.ensureLayout(for:)`; update lightweight typing state inline, but defer full restyles to the next main-runloop turn to avoid AppKit reentrancy traps.
