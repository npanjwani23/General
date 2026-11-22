import FamilyControls
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthorized = false
    @Published var isLocked = false
    @Published var lockedAt: Date?
    @Published var tags: [PairedTag] = []
    @Published var emergencyUsed = 0
    @Published var message: String?
    @Published var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }

    private let screenTime = ScreenTimeService()
    private let nfc = NFCService()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let selection = "selection"
        static let isLocked = "isLocked"
        static let lockedAt = "lockedAt"
    }

    init() {
        if let data = defaults.data(forKey: Keys.selection),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        isLocked = defaults.bool(forKey: Keys.isLocked)
        lockedAt = defaults.object(forKey: Keys.lockedAt) as? Date
        tags = TagStore.loadTags()
        emergencyUsed = TagStore.emergencyUsed()
        refresh()
    }

    // MARK: Derived state

    var emergencyRemaining: Int {
        max(0, TagStore.emergencyLimit - emergencyUsed)
    }

    var selectionCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var isReady: Bool {
        isAuthorized && selectionCount > 0 && !tags.isEmpty
    }

    // MARK: Lifecycle

    /// Called on launch and whenever the app returns to the foreground.
    func refresh() {
        isAuthorized = screenTime.isAuthorized
        // Shields persist on their own, but re-applying keeps the system
        // state and our saved state from drifting apart.
        if isLocked && isAuthorized {
            screenTime.applyShields(for: selection)
        }
    }

    // MARK: Setup

    func requestAuthorization() async {
        do {
            try await screenTime.requestAuthorization()
        } catch {
            message = "Screen Time access was not granted. Latch cannot block apps without it."
        }
        isAuthorized = screenTime.isAuthorized
    }

    func pairTag() async {
        guard !isLocked else { return }
        do {
            let uid = try await nfc.scan(prompt: "Hold your iPhone near the tag you want to pair.")
            if tags.contains(where: { $0.id == uid }) {
                message = "That tag is already paired."
                return
            }
            tags.append(PairedTag(id: uid, name: "Tag \(tags.count + 1)"))
            TagStore.saveTags(tags)
        } catch {
            report(error)
        }
    }

    func removeTags(at offsets: IndexSet) {
        guard !isLocked else { return }
        tags.remove(atOffsets: offsets)
        TagStore.saveTags(tags)
    }

    // MARK: Lock and unlock

    /// Scans a tag. A paired tag toggles the lock, anything else is rejected.
    func tapTag() async {
        guard isLocked || isReady else { return }
        do {
            let prompt = isLocked
                ? "Hold your iPhone near your tag to unlock."
                : "Hold your iPhone near your tag to lock."
            let uid = try await nfc.scan(prompt: prompt)
            guard tags.contains(where: { $0.id == uid }) else {
                message = "That tag is not paired with Latch."
                return
            }
            if isLocked {
                unlock()
            } else {
                lock()
            }
        } catch {
            report(error)
        }
    }

    func emergencyUnlock() {
        guard isLocked, emergencyRemaining > 0 else { return }
        emergencyUsed += 1
        TagStore.setEmergencyUsed(emergencyUsed)
        unlock()
    }

    private func lock() {
        screenTime.applyShields(for: selection)
        isLocked = true
        lockedAt = Date()
        saveLockState()
    }

    private func unlock() {
        screenTime.clearShields()
        isLocked = false
        lockedAt = nil
        saveLockState()
    }

    // MARK: Persistence

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Keys.selection)
        }
    }

    private func saveLockState() {
        defaults.set(isLocked, forKey: Keys.isLocked)
        defaults.set(lockedAt, forKey: Keys.lockedAt)
    }

    private func report(_ error: Error) {
        if case NFCScanError.cancelled = error { return }
        message = error.localizedDescription
    }
}
