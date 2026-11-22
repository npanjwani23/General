import FamilyControls
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var showPicker = false
    @State private var showTags = false
    @State private var confirmEmergency = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    lockButton
                    statusText
                    if state.isLocked {
                        emergencySection
                    } else {
                        setupSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .navigationTitle("Latch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $state.selection)
        .sheet(isPresented: $showTags) {
            TagsView().environmentObject(state)
        }
        .alert("Latch", isPresented: messageBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.message ?? "")
        }
        .alert("Use an emergency unlock?", isPresented: $confirmEmergency) {
            Button("Unlock", role: .destructive) { state.emergencyUnlock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have \(state.emergencyRemaining) of \(TagStore.emergencyLimit) left. They do not come back.")
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            // While the tags sheet is up, it shows the alert instead.
            get: { state.message != nil && !showTags },
            set: { if !$0 { state.message = nil } }
        )
    }

    // MARK: Lock button

    private var lockButton: some View {
        Button {
            Task { await state.tapTag() }
        } label: {
            ZStack {
                Circle()
                    .fill(state.isLocked ? Color.orange : Color(.secondarySystemBackground))
                Circle()
                    .strokeBorder(Color.orange.opacity(state.isLocked ? 0 : 0.6), lineWidth: 2)
                VStack(spacing: 10) {
                    Image(systemName: state.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 56, weight: .semibold))
                    Text(state.isLocked ? "Tap tag to unlock" : "Tap tag to lock")
                        .font(.headline)
                }
                .foregroundStyle(state.isLocked ? Color.black : Color.orange)
            }
            .frame(width: 230, height: 230)
        }
        .buttonStyle(.plain)
        .disabled(!state.isLocked && !state.isReady)
        .opacity(!state.isLocked && !state.isReady ? 0.4 : 1)
    }

    @ViewBuilder
    private var statusText: some View {
        if state.isLocked, let lockedAt = state.lockedAt {
            VStack(spacing: 6) {
                Text("Locked")
                    .font(.title2.bold())
                Text(lockedAt, style: .timer)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if state.isReady {
            Text("Ready. Blocking \(state.selectionCount) item\(state.selectionCount == 1 ? "" : "s").")
                .foregroundStyle(.secondary)
        } else {
            Text("Finish setup below to start.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Setup rows (unlocked only)

    private var setupSection: some View {
        VStack(spacing: 12) {
            SetupRow(
                icon: "hourglass",
                title: "Screen Time access",
                detail: state.isAuthorized ? "Allowed" : "Required to block apps",
                done: state.isAuthorized
            ) {
                Task { await state.requestAuthorization() }
            }
            .disabled(state.isAuthorized)

            SetupRow(
                icon: "square.grid.2x2",
                title: "Blocked apps and sites",
                detail: state.selectionCount > 0 ? "\(state.selectionCount) selected" : "Choose what to block",
                done: state.selectionCount > 0
            ) {
                showPicker = true
            }
            .disabled(!state.isAuthorized)

            SetupRow(
                icon: "wave.3.right",
                title: "NFC tags",
                detail: state.tags.isEmpty ? "Pair your first tag" : "\(state.tags.count) paired",
                done: !state.tags.isEmpty
            ) {
                showTags = true
            }
        }
    }

    // MARK: Emergency (locked only)

    private var emergencySection: some View {
        VStack(spacing: 8) {
            Button("Emergency unlock") {
                confirmEmergency = true
            }
            .disabled(state.emergencyRemaining == 0)
            Text("\(state.emergencyRemaining) of \(TagStore.emergencyLimit) remaining")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }
}

private struct SetupRow: View {
    let icon: String
    let title: String
    let detail: String
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(done ? Color.green : Color.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
