import Foundation
import SwiftUI

struct ContextWindowIndicator: View {
    let summary: ConversationUsageSummary
    var showsTooltipOverride = false

    @State private var isHovered = false

    private let hitTargetSize: CGFloat = 22
    private let circleDiameter: CGFloat = 14
    private let strokeWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.28), lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: summary.contextUsageFraction)
                .stroke(progressColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: circleDiameter, height: circleDiameter)
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
        .accessibilityLabel("Context window usage")
        .accessibilityValue(accessibilityValue)
        .onHover { isHovered = $0 }
        .overlay(alignment: .top) {
            if isHovered || showsTooltipOverride {
                ContextWindowTooltip(summary: summary)
                    .fixedSize()
                    .offset(y: -118)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered || showsTooltipOverride)
    }

    private var progressColor: Color {
        switch summary.contextUsageFraction {
        case 0.9...:
            return .red
        case 0.75..<0.9:
            return .orange
        default:
            return .secondary
        }
    }

    private var accessibilityValue: String {
        if summary.hasReportedUsage {
            return "\(summary.contextUsagePercent)% full"
        }
        return "No usage reported yet"
    }
}

private struct ContextWindowTooltip: View {
    let summary: ConversationUsageSummary

    var body: some View {
        VStack(spacing: 8) {
            Text("Context window:")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            if summary.hasReportedUsage {
                Text("\(summary.contextUsagePercent)% full")
                    .font(.headline.weight(.semibold))
                Text("\(Self.tokenText(summary.contextUsedTokens)) / \(Self.tokenText(summary.contextWindowSize)) tokens used")
                    .font(.callout.weight(.semibold))
            } else {
                Text("No usage yet")
                    .font(.headline.weight(.semibold))
                Text("\(Self.tokenText(summary.contextWindowSize)) token window")
                    .font(.callout.weight(.semibold))
            }

            Text("Session spend: \(Self.costText(summary.totalCostUsd))")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }
        }
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return compactDecimal(Double(value) / 1_000_000) + "M"
        }
        if value >= 1_000 {
            return compactDecimal(Double(value) / 1_000) + "k"
        }
        return value.formatted()
    }

    private static func compactDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func costText(_ value: Double) -> String {
        if value > 0, value < 0.01 {
            return String(format: "$%.4f", value)
        }
        return String(format: "$%.2f", value)
    }
}
