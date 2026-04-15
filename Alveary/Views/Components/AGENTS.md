## Shared View Components

These rules cover shared UI components under `Alveary/Views/Components/`.

## AppTextEditor And AppKitTextView

- Keep the placeholder drawn inside `AppKitTextView` instead of reintroducing a SwiftUI overlay so it shares the real `NSTextView` insets and caret positioning.
