import SwiftUI

/// The whole app on one screen. Light while unlocked, dark while locked, so
/// the state reads at a glance. Everything else lives in sheets.
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("didShowSetup") private var didShowSetup = false
    @State private var sheet: HomeSheet?
    @State private var confirmEmergency = false
    @State private var holdProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)
            Spacer(minLength: 24)
            mark
            modeInfo
                .padding(.top, 28)
            Spacer(minLength: 24)
            control
            footer
                .frame(height: 44)
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlay(alignment: .topTrailing) { settingsButton }
        .animation(.easeInOut(duration: 0.35), value: state.isLocked)
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

    // MARK: Header: today's total, or the live lock timer

    @ViewBuilder
    private var header: some View {
        if state.isLocked, let lockedAt = state.lockedAt {
            VStack(spacing: 6) {
                Text("Locked for")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: lockedAt, by: 1)) { context in
                    Text(DurationText.clock(context.date.timeIntervalSince(lockedAt)))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                if let caption = state.lockCaption {
                    Label(caption, systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Button { sheet = .stats } label: {
                TimelineView(.everyMinute) { context in
                    HStack(spacing: 6) {
                        Text(DurationText.short(state.lockedToday(now: context.date)))
                            .fontWeight(.semibold)
                        Text("today")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows time locked this week")
        }
    }

    // MARK: Center mark

    private var mark: some View {
        ZStack {
            Circle()
                .fill(state.isLocked ? Color.orange : Color(.secondarySystemBackground))
            Circle()
                .strokeBorder(Color.orange.opacity(state.isLocked ? 0 : 0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Image(systemName: state.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(state.isLocked ? Color.black : Color.orange)
        }
        .frame(width: 210, height: 210)
        .accessibilityHidden(true)
    }

    // MARK: Mode name and what it blocks

    private var modeInfo: some View {
        VStack(spacing: 6) {
            Text(state.displayMode?.name ?? "Focus")
                .font(.title2.weight(.semibold))
            Text(state.displayMode?.summary ?? "Nothing blocked yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !state.isLocked {
                Button { sheet = .modes } label: {
                    HStack(spacing: 4) {
                        Text("Manage modes")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Bottom action

    private var control: some View {
        LockControl(
            title: controlTitle,
            holdTitle: "Keep holding to lock",
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
        if state.isLocked { return "Tap tag to unlock" }
        if state.isReady { return "Tap or hold to lock" }
        return state.nextSetupStep.map { "Set up: \($0)" } ?? "Finish setup"
    }

    @ViewBuilder
    private var footer: some View {
        if state.isLocked {
            Button {
                confirmEmergency = true
            } label: {
                Text("Emergency unlock · \(state.emergencyRemaining) left")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(.secondary)
            .disabled(state.emergencyRemaining == 0)
        } else if state.isReady {
            Text("Hold for 3 seconds to lock without your tag. Unlocking always needs the tag.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Settings (unlocked only, so a lock cannot be undone from here)

    @ViewBuilder
    private var settingsButton: some View {
        if !state.isLocked {
            Button { sheet = .setup } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 12)
            .accessibilityLabel("Settings")
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
