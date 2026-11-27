import UIKit

/// Small wrapper so every lock, unlock and error feels the same.
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Light tick, used while a hold-to-lock is in progress.
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Very light tap for button presses.
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    /// Selection change, such as picking a mode.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
