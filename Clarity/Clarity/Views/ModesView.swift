import FamilyControls
import SwiftUI

private enum ModeRoute: Hashable {
    case new
    case edit(UUID)
}

/// List of modes. Tap one to make it active, the info button to edit it.
struct ModesView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ModeRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(state.modes) { mode in
                        ModeRow(mode: mode,
                                isActive: mode.id == state.activeMode?.id,
                                select: { state.activate(mode) },
                                edit: { path.append(.edit(mode.id)) })
                    }
                    .onDelete { state.deleteModes(at: $0) }
                    .deleteDisabled(!state.canDeleteModes)
                } footer: {
                    Text("Tap a mode to make it the one your tag locks. Up to \(Mode.limit) modes.")
                }

                Section {
                    Button {
                        path.append(.new)
                    } label: {
                        Label("New mode", systemImage: "plus")
                    }
                    .disabled(!state.canAddMode)
                }
            }
            .navigationTitle("Modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: ModeRoute.self) { route in
                switch route {
                case .new:
                    ModeEditor(mode: nil)
                case .edit(let id):
                    if let mode = state.modes.first(where: { $0.id == id }) {
                        ModeEditor(mode: mode)
                    }
                }
            }
            .messageAlert(state)
        }
    }
}

private struct ModeRow: View {
    let mode: Mode
    let isActive: Bool
    let select: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isActive ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                            .foregroundStyle(.primary)
                        Text(mode.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Button(action: edit) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(mode.name)")
        }
    }
}

/// Create or edit one mode: its name and what it blocks.
struct ModeEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    private let original: Mode?
    @State private var name: String
    @State private var selection: FamilyActivitySelection
    @State private var showPicker = false

    init(mode: Mode?) {
        original = mode
        _name = State(initialValue: mode?.name ?? "")
        _selection = State(initialValue: mode?.selection ?? FamilyActivitySelection())
    }

    private var draft: Mode {
        Mode(id: original?.id ?? UUID(), name: name, selection: selection)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Deep Work, No Social, Sleep…", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }

            Section {
                if state.isAuthorized {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text("Choose apps and sites")
                            Spacer()
                            Text(draft.itemCount == 0 ? "None" : "\(draft.itemCount)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                } else {
                    Button("Allow Screen Time access") {
                        Task { await state.requestAuthorization() }
                    }
                }
            } header: {
                Text("Blocked")
            } footer: {
                if let problem = draft.problem {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text(state.isAuthorized
                         ? draft.summary + "."
                         : "Clarity needs Screen Time access before it can list your apps.")
                }
            }
        }
        .navigationTitle(original == nil ? "New mode" : "Edit mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(draft.problem != nil)
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
    }

    private func save() {
        if let original {
            state.updateMode(Mode(id: original.id, name: name, selection: selection))
        } else if state.addMode(name: name, selection: selection),
                  let created = state.modes.last {
            // A mode you just made is almost always the one you want next.
            state.activate(created)
        }
        dismiss()
    }
}
