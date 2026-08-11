import SwiftUI

/// The two-step arm/confirm state machine behind the row's archive/delete pill. Split out of
/// `SidebarView+ThreadRow.swift` to keep that type under the body-length limit; the `@State` it
/// drives is internal on `SidebarThreadRow` for the same reason.
extension SidebarThreadRow {
    func cleanupPressGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isCleanupButtonPressed else {
                    return
                }

                setCleanupButtonPressed(true)
                pauseCleanupConfirmation()
            }
            .onEnded { value in
                let wasArmed = isCleanupConfirmationArmed
                setCleanupButtonPressed(false)

                if cleanupButtonContains(value.location, width: width) {
                    handleCleanupButtonClick()
                } else if wasArmed && !isHoveringCleanupButton {
                    resumeCleanupConfirmation()
                }
            }
    }

    private func cleanupButtonContains(_ location: CGPoint, width: CGFloat) -> Bool {
        location.x >= 0
            && location.x <= width
            && location.y >= 0
            && location.y <= Self.cleanupButtonSize
    }

    private func setCleanupButtonPressed(_ pressed: Bool) {
        withAnimation(.easeOut(duration: 0.08)) {
            isCleanupButtonPressed = pressed
        }
    }

    func handleCleanupButtonClick() {
        if isCleanupConfirmationArmed {
            clearCleanupConfirmation(forCommit: true)
            onConfirmCleanup()
        } else {
            armCleanupConfirmation()
        }
    }

    private func armCleanupConfirmation() {
        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationRemainingNanoseconds = nil
        cleanupWidthAnimationTask?.cancel()
        isCleanupControlCollapsing = false
        isCleanupControlCollapsingToHidden = false

        withAnimation(.easeInOut(duration: Self.cleanupWidthAnimationDuration)) {
            isCleanupConfirmationArmed = true
            isCleanupConfirmationChromeVisible = true
        }
        scheduleCleanupConfirmationTimeout(nanoseconds: Self.cleanupConfirmationTimeoutNanoseconds)
        if isHoveringCleanupButton {
            pauseCleanupConfirmation()
        }
    }

    private func scheduleCleanupConfirmationTimeout(nanoseconds: UInt64) {
        cleanupConfirmationDeadline = Date().addingTimeInterval(Double(nanoseconds) / 1_000_000_000)

        cleanupConfirmationResetTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                clearCleanupConfirmation()
            }
        }
    }

    func pauseCleanupConfirmation() {
        guard isCleanupConfirmationArmed,
              cleanupConfirmationResetTask != nil,
              cleanupConfirmationRemainingNanoseconds == nil else {
            return
        }

        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationResetTask = nil
        let remainingSeconds = max(cleanupConfirmationDeadline?.timeIntervalSinceNow ?? 0, 0)
        cleanupConfirmationDeadline = nil
        cleanupConfirmationRemainingNanoseconds = UInt64(remainingSeconds * 1_000_000_000)
    }

    func resumeCleanupConfirmation() {
        guard isCleanupConfirmationArmed,
              let remainingNanoseconds = cleanupConfirmationRemainingNanoseconds else {
            return
        }

        cleanupConfirmationRemainingNanoseconds = nil
        scheduleCleanupConfirmationTimeout(nanoseconds: remainingNanoseconds)
    }

    /// `forCommit` marks the confirm click, which always removes the row. That case drops the pill
    /// instantly and to zero width: animating a 0.18s collapse would run concurrently with the
    /// `List` pulling the row out, and the two together read as the pill lagging the row. The
    /// timeout path keeps the animation and its hover-derived landing state.
    private func clearCleanupConfirmation(forCommit: Bool = false) {
        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationResetTask = nil
        cleanupWidthAnimationTask?.cancel()
        cleanupConfirmationDeadline = nil
        cleanupConfirmationRemainingNanoseconds = nil

        guard isCleanupConfirmationArmed else {
            return
        }

        let shouldHideAfterCollapse = sidebarThreadCleanupCollapsesToHidden(
            forCommit: forCommit,
            isHovering: isHovering
        )
        var instantTransaction = Transaction(animation: nil)
        instantTransaction.disablesAnimations = true
        withTransaction(instantTransaction) { isCleanupConfirmationChromeVisible = false }

        let collapse = {
            isCleanupControlCollapsing = true
            isCleanupControlCollapsingToHidden = shouldHideAfterCollapse
            isCleanupConfirmationArmed = false
        }
        if forCommit {
            withTransaction(instantTransaction, collapse)
        } else {
            withAnimation(.easeInOut(duration: Self.cleanupWidthAnimationDuration), collapse)
        }

        // Still scheduled for the commit case: the row is normally gone before it fires and
        // `onDisappear` cancels it, but a failed archive/delete leaves the row mounted and this
        // is what restores the hover icon.
        cleanupWidthAnimationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.cleanupWidthAnimationNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            isCleanupControlCollapsing = false
            isCleanupControlCollapsingToHidden = false
        }
    }
}
