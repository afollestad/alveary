import CoreGraphics

// Shared by submitted-response bubbles and live question cards so both Prompt
// render modes keep matching chrome after the SwiftUI prompt rows were removed.
let promptBlockPadding: CGFloat = 14
let promptQuestionCardPadding: CGFloat = 12
let promptBlockCornerRadius: CGFloat = AppCornerRadius.standard
let promptSubmittedPairSpacing: CGFloat = 8
