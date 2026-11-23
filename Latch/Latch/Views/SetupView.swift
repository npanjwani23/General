import SwiftUI

/// Setup checklist and settings in one place: Screen Time access, what the
/// active mode blocks, paired tags, and emergency unlocks left. Opens on
/// first launch and from the gear button while unlocked.
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StepRow(number: 1, title: "Screen Time access",
                            detail: state.isAuthorized ? "Allowed" : "Lets Latch block apps",
                            done: state.isAuthorized)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !state.isAuthorized else { return }
                            Task { await state.requestAuthorization() }
                        }

                    NavigationLink {
                        ModeEditor(mode: state.activeMode)
                    } label: {
                        StepRow(number: 2, title: "Apps to block",
                                detail: "\(state.activeMode?.name ?? "Focus"): \(state.activeMode?.summary ?? "")",
                                done: (state.activeMode?.itemCount ?? 0) > 0)
                    }

                    StepRow(number: 3, title: "Pair a tag",
                            detail: state.tags.isEmpty ? "Below" : "\(state.tags.count) paired",
                            done: !state.tags.isEmpty)
                } header: {
                    Text("Setup")
                } footer: {
                    if state.isReady {
                        Text("All set. Tap your tag, or hold the button for 3 seconds, to lock.")
                    }
                }

                Section {
                    ForEach(state.tags) { tag in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name)
                            Text(tag.id)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { state.removeTags(at: $0) }

                    Button {
                        Task { await state.pairTag() }
                    } label: {
                        Label("Pair a new tag", systemImage: "plus")
                    }
                } header: {
                    Text("NFC tags")
                } footer: {
                    Text("Any paired tag can lock and unlock. Swipe to remove one.")
                }

                Section {
                    HStack {
                        Text("Emergency unlocks")
                        Spacer()
                        Text("\(state.emergencyRemaining) of \(TagStore.emergencyLimit) left")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("For when your tag is lost. They do not come back, even if you reinstall Latch.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .messageAlert(state)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.orange.opacity(0.15))
                if done {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}
