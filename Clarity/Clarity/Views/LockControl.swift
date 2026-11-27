import SwiftUI

/// The one action button at the bottom of the home screen.
///
/// Tap runs `onTap` (scan a tag). When `allowsHold` is on, pressing and
/// holding for `holdSeconds` runs `onHold` instead, with the button filling
/// up and a light tick each second so it is clear something is happening.
struct LockControl: View {
    let title: String
    let holdTitle: String
    let allowsHold: Bool
    let prominent: Bool
    @Binding var progress: Double
    let onTap: () -> Void
    let onHold: () -> Void

    static let holdSeconds: Double = 3

    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var completed = false
    @State private var pressed = false

    /// Shorter than this counts as a tap, not the start of a hold.
    private let tapThreshold: TimeInterval = 0.35

    var body: some View {
        label
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onLongPressGesture(minimumDuration: allowsHold ? Self.holdSeconds : 60,
                                maximumDistance: 40,
                                perform: holdFinished,
                                onPressingChanged: pressingChanged)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .modifier(HoldAccessibilityAction(enabled: allowsHold, action: onHold))
    }

    /// Still-style frosted bar: a translucent wash that fills with color
    /// while you hold. `prominent` is the locked (dark) look.
    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let fill = prominent ? Theme.glow : Theme.accent
        return ZStack(alignment: .leading) {
            shape.fill(.ultraThinMaterial)
            shape.fill(fill.opacity(pressed ? 0.26 : (prominent ? 0.16 : 0.14)))
            GeometryReader { proxy in
                shape
                    .fill(fill.opacity(prominent ? 0.55 : 0.9))
                    .frame(width: max(0, proxy.size.width * progress))
            }
            Text(progress > 0 ? holdTitle : title)
                .font(Theme.font(17, .bold))
                .foregroundStyle(prominent ? Theme.nightInk : (progress > 0.5 ? Color.white : Theme.ink))
                .frame(maxWidth: .infinity)
                .animation(nil, value: progress)
        }
        .frame(height: 64)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(prominent ? Theme.glow.opacity(0.38) : Color.white.opacity(0.95), lineWidth: 1)
        }
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: pressed)
    }

    private func pressingChanged(_ pressing: Bool) {
        pressed = pressing
        if pressing {
            Haptics.soft()
            completed = false
            pressStart = Date()
            guard allowsHold else { return }
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                // Wait out the tap window so a quick tap does not flash the fill.
                try? await Task.sleep(nanoseconds: UInt64(tapThreshold * 1_000_000_000))
                guard !Task.isCancelled else { return }
                Haptics.tick()
                withAnimation(.linear(duration: Self.holdSeconds - tapThreshold)) {
                    progress = 1
                }
                var second = 1
                while second < Int(Self.holdSeconds) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    Haptics.tick()
                    second += 1
                }
            }
        } else {
            holdTask?.cancel()
            holdTask = nil
            let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
            pressStart = nil
            if !completed {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                // With hold on, letting go mid-hold cancels. With hold off,
                // any press is just a tap, however slow.
                if held < tapThreshold || !allowsHold { onTap() }
            }
        }
    }

    private func holdFinished() {
        guard allowsHold else { return }
        completed = true
        holdTask?.cancel()
        holdTask = nil
        Haptics.heavy()
        onHold()
        withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
    }
}

private struct HoldAccessibilityAction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "Lock without tag", action)
        } else {
            content
        }
    }
}
