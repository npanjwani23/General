import SwiftUI

struct TagsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                } footer: {
                    Text("Any paired tag can lock and unlock. Swipe to remove one.")
                }

                Section {
                    Button {
                        Task { await state.pairTag() }
                    } label: {
                        Label("Pair a new tag", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("NFC tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Latch", isPresented: messageBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.message ?? "")
            }
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { state.message != nil },
            set: { if !$0 { state.message = nil } }
        )
    }
}
