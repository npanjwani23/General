import SwiftUI

/// Clarity's look: soft frosted cards over slowly drifting color blobs.
/// Light lavender while open, deep indigo while locked.
enum Theme {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: alpha)
    }

    // Open
    static let background = hex(0xF4F4F8)
    static let ink = hex(0x1C1B2E)
    static let subtle = hex(0x55546B)
    static let accent = hex(0x5B5BD6)
    static let lavender = hex(0xC9C8F5)
    static let mint = hex(0xBFE3DC)
    static let quiet = hex(0xDDDDE8)

    // Locked
    static let night = hex(0x17162B)
    static let nightInk = hex(0xF1F0FF)
    static let nightSubtle = hex(0xB5B3D6)
    static let glow = hex(0xA9A8FF)
    static let nightBlobA = hex(0x2E2C66)
    static let nightBlobB = hex(0x1F3B45)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Background: the base color plus two soft blobs that drift slowly, so the
/// screen feels alive without asking for attention.
struct BlobBackground: View {
    let locked: Bool
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                (locked ? Theme.night : Theme.background)
                Circle()
                    .fill(locked ? Theme.nightBlobA : Theme.lavender)
                    .frame(width: w * 0.8, height: w * 0.8)
                    .blur(radius: 30)
                    .offset(x: w * (drift ? 0.38 : 0.28), y: drift ? -w * 0.28 : -w * 0.18)
                Circle()
                    .fill(locked ? Theme.nightBlobB : Theme.mint)
                    .frame(width: w * 0.62, height: w * 0.62)
                    .blur(radius: 30)
                    .offset(x: -w * (drift ? 0.36 : 0.26), y: proxy.size.height * (drift ? 0.22 : 0.3))
            }
            .frame(width: w, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }
}

/// A frosted card. `dark` is for the locked screen.
struct FrostCard: ViewModifier {
    var dark = false
    var radius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.14) : Color.white.opacity(0.95), lineWidth: 1)
            }
    }
}

extension View {
    func frostCard(dark: Bool = false, radius: CGFloat = 26) -> some View {
        modifier(FrostCard(dark: dark, radius: radius))
    }
}

/// Press feel for every tappable thing: it dips slightly, gets a
/// translucent wash, springs back, and gives a soft tick.
struct SquishStyle: ButtonStyle {
    var radius: CGFloat = 22
    var dark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill((dark ? Theme.glow : Theme.accent).opacity(configuration.isPressed ? 0.14 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { Haptics.soft() }
            }
    }
}
