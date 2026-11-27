import FamilyControls
import SwiftUI

/// The whole app on one screen. Open: your week and your modes. Locked:
/// the running timer and what is set aside. Everything else lives in sheets.
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("didShowSetup") private var didShowSetup = false
    @State private var sheet: HomeSheet?
    @State private var confirmEmergency = false
    @State private var holdProgress: Double = 0

    var body: some View {
        ZStack {
            BlobBackground(locked: state.isLocked)
            VStack(spacing: 14) {
                if state.isLocked {
                    LockedContent()
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                } else {
                    OpenContent(sheet: $sheet)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
                Spacer(minLength: 0)
                control
                footer
                    .frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: state.isLocked)
        .onChange(of: state.isLocked) { locked in
            // A schedule can lock while a sheet is open; nothing in them may
            // be changed while locked, so close them.
            if locked { sheet = nil }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .setup: SetupView()
                case .modes: ModesView()
                case .stats: StatsView()
                }
            }
            .environmentObject(state)
            .font(.system(.body, design: .rounded))
        }
        .messageAlert(state, isActive: sheet == nil)
        .alert("Use an emergency unlock?", isPresented: $confirmEmergency) {
            Button("Unlock", role: .destructive) { state.emergencyUnlock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have \(state.emergencyRemaining) of \(TagStore.emergencyLimit) left. They do not come back.")
        }
        .onAppear {
            if !didShowSetup && !state.isReady && !state.isLocked {
                didShowSetup = true
                sheet = .setup
            }
        }
    }

    // MARK: Bottom action

    private var control: some View {
        LockControl(
            title: controlTitle,
            holdTitle: "Keep holding…",
            allowsHold: !state.isLocked && state.isReady,
            prominent: state.isLocked,
            progress: $holdProgress,
            onTap: {
                if state.isLocked || state.isReady {
                    Task { await state.tapTag() }
                } else {
                    sheet = .setup
                }
            },
            onHold: { state.holdToLock() }
        )
    }

    private var controlTitle: String {
        if state.isLocked { return "Tap your tag to finish" }
        if state.isReady { return "Tap your tag to begin" }
        return state.nextSetupStep.map { "Set up: \($0)" } ?? "Finish setup"
    }

    @ViewBuilder
    private var footer: some View {
        if state.isLocked {
            Button {
                confirmEmergency = true
            } label: {
                Text("Emergency unlock · \(state.emergencyRemaining) left")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.nightSubtle)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .disabled(state.emergencyRemaining == 0)
        } else if state.isReady {
            Text("or hold for 3 seconds")
                .font(Theme.font(13))
                .foregroundStyle(Theme.subtle)
        }
    }
}

// MARK: - Open

private struct OpenContent: View {
    @EnvironmentObject private var state: AppState
    @Binding var sheet: HomeSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            WeekCard { sheet = .stats }
            Text("Modes")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.subtle)
                .padding(.horizontal, 6)
                .padding(.top, 4)
            ModeGrid { sheet = .modes }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.subtle)
                Text("You're open")
                    .font(Theme.font(30, .bold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { sheet = .setup } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
                    .frostCard(radius: 16)
            }
            .buttonStyle(SquishStyle(radius: 16))
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 6)
    }
}

/// This week's bars and today's total. Tap for the full stats.
private struct WeekCard: View {
    @EnvironmentObject private var state: AppState
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            TimelineView(.everyMinute) { context in
                let days = state.lockedLastSevenDays(now: context.date)
                let peak = max(days.map(\.seconds).max() ?? 0, 60 * 60)
                let week = days.reduce(0) { $0 + $1.seconds }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Last 7 days")
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.subtle)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(index == days.count - 1 ? Theme.accent
                                          : (day.seconds > 0 ? Theme.lavender : Theme.quiet))
                                    .frame(height: max(8, 76 * day.seconds / peak))
                                Text(day.day.formatted(.dateTime.weekday(.narrow)))
                                    .font(Theme.font(11, .medium))
                                    .foregroundStyle(Theme.subtle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 96, alignment: .bottom)
                    HStack(alignment: .firstTextBaseline) {
                        Text(DurationText.short(state.lockedToday(now: context.date)))
                            .font(Theme.font(26, .bold))
                            .foregroundStyle(Theme.ink)
                        Text("today")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.subtle)
                        Spacer()
                        Text("\(DurationText.short(week)) this week")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.subtle)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frostCard()
            }
        }
        .buttonStyle(SquishStyle(radius: 26))
        .accessibilityHint("Shows time locked this week")
    }
}

/// Modes as cards. Tap to pick the one your tag locks; the last card opens
/// the full list to add or edit.
private struct ModeGrid: View {
    @EnvironmentObject private var state: AppState
    let manage: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let shown = Array(state.modes.prefix(3))
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(shown) { mode in
                ModeCard(mode: mode, selected: mode.id == state.activeMode?.id) {
                    if mode.id != state.activeMode?.id {
                        Haptics.select()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { state.activate(mode) }
                    }
                }
                .contextMenu {
                    Button { manage() } label: { Label("Edit modes", systemImage: "pencil") }
                }
            }
            Button(action: manage) {
                VStack(spacing: 6) {
                    Image(systemName: state.modes.count > 3 ? "square.grid.2x2" : "plus")
                        .font(.system(size: 18, weight: .semibold))
                    Text(state.modes.count > 3 ? "All modes" : "New mode")
                        .font(Theme.font(15, .semibold))
                }
                .foregroundStyle(Theme.subtle)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            }
            .buttonStyle(SquishStyle(radius: 22))
        }
    }
}

private struct ModeCard: View {
    let mode: Mode
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(mode.name)
                        .font(Theme.font(17, .bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer(minLength: 10)
                Text(cardSummary)
                    .font(Theme.font(13))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.subtle)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? Theme.accent : Color.white.opacity(0.62))
                    .shadow(color: selected ? Theme.accent.opacity(0.35) : .clear, radius: 12, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.95), lineWidth: 1)
            }
        }
        .buttonStyle(SquishStyle(radius: 22))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cardSummary: String {
        mode.itemCount == 0 ? "Nothing chosen yet" : mode.summary.replacingOccurrences(of: "Blocks ", with: "")
    }
}

// MARK: - Locked

private struct LockedContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.displayMode?.name ?? "Focus")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.nightSubtle)
                Text("You're in focus")
                    .font(Theme.font(30, .bold))
                    .foregroundStyle(Theme.nightInk)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 46)

            timerCard
            if let mode = state.displayMode, mode.itemCount > 0 {
                SetAsideCard(mode: mode)
            }
        }
    }

    private var timerCard: some View {
        TimelineView(.periodic(from: state.lockedAt ?? .now, by: 1)) { context in
            let start = state.lockedAt ?? context.date
            let end = state.lockEnd
            VStack(spacing: 8) {
                Text("Clear for")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.nightSubtle)
                Text(DurationText.clock(context.date.timeIntervalSince(start)))
                    .font(Theme.font(48, .bold).monospacedDigit())
                    .foregroundStyle(Theme.nightInk)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let end, end > start {
                    let fraction = min(1, max(0, context.date.timeIntervalSince(start) / end.timeIntervalSince(start)))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(Theme.glow).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 8)
                    .padding(.top, 6)
                }
                HStack {
                    Text("Started \(start.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    Text(end.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" } ?? "Ends with your tag")
                }
                .font(Theme.font(13))
                .foregroundStyle(Theme.nightSubtle)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frostCard(dark: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The apps, categories and sites this lock is holding back.
private struct SetAsideCard: View {
    let mode: Mode
    private let maxChips = 5

    var body: some View {
        let apps = Array(mode.selection.applicationTokens)
        let categories = Array(mode.selection.categoryTokens)
        let sites = Array(mode.selection.webDomainTokens)
        let shownApps = Array(apps.prefix(maxChips))
        let shownCategories = Array(categories.prefix(max(0, maxChips - shownApps.count)))
        let hidden = mode.itemCount - shownApps.count - shownCategories.count

        VStack(alignment: .leading, spacing: 12) {
            Text("Set aside")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.nightSubtle)
            FlowLayout(spacing: 8) {
                ForEach(shownApps, id: \.self) { token in
                    chip { Label(token) }
                }
                ForEach(shownCategories, id: \.self) { token in
                    chip { Label(token) }
                }
                if hidden > 0 {
                    chip { Text("+\(hidden) more") }
                }
            }
            .labelStyle(ChipLabelStyle())
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostCard(dark: true)
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.font(13))
            .foregroundStyle(Theme.nightInk)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(Theme.glow.opacity(0.16), in: Capsule())
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            configuration.title
                .lineLimit(1)
        }
    }
}

/// Lays chips out left to right, wrapping to new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum HomeSheet: String, Identifiable {
    case setup, modes, stats
    var id: String { rawValue }
}

extension View {
    /// Shows `state.message` as an alert. Only one presenter should be active
    /// at a time, so the home screen hands off while a sheet is up.
    func messageAlert(_ state: AppState, isActive: Bool = true) -> some View {
        alert("Clarity", isPresented: Binding(
            get: { isActive && state.message != nil },
            set: { if !$0 { state.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.message ?? "")
        }
    }
}
