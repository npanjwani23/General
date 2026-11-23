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
    @Published private(set) var modes: [Mode] = []
    @Published private(set) var activeModeID: UUID?
    @Published private(set) var sessions: [LockSession] = []

    private let screenTime = ScreenTimeService()
    private let nfc = NFCService()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let legacySelection = "selection"
        static let modes = "modes"
        static let activeModeID = "activeModeID"
        static let isLocked = "isLocked"
        static let lockedAt = "lockedAt"
    }

    init() {
        loadModes()
        isLocked = defaults.bool(forKey: Keys.isLocked)
        lockedAt = defaults.object(forKey: Keys.lockedAt) as? Date
        tags = TagStore.loadTags() ?? []
        emergencyUsed = TagStore.emergencyUsed() ?? 0
        sessions = LockLog.load(defaults)
        refresh()
    }

    // MARK: Derived state

    var emergencyRemaining: Int {
        max(0, TagStore.emergencyLimit - emergencyUsed)
    }

    var activeMode: Mode? {
        modes.first { $0.id == activeModeID } ?? modes.first
    }

    var isReady: Bool {
        isAuthorized && (activeMode?.itemCount ?? 0) > 0 && !tags.isEmpty
    }

    /// What is still missing before the first lock, in setup order.
    var nextSetupStep: String? {
        if !isAuthorized { return "Allow Screen Time access" }
        if (activeMode?.itemCount ?? 0) == 0 { return "Choose apps to block" }
        if tags.isEmpty { return "Pair a tag" }
        return nil
    }

    func lockedToday(now: Date = Date()) -> TimeInterval {
        LockLog.lockedSeconds(in: LockLog.day(containing: now), sessions: sessions,
                              liveStart: isLocked ? lockedAt : nil, now: now)
    }

    /// Seconds locked on each of the last 7 days, oldest first.
    func lockedLastSevenDays(now: Date = Date()) -> [(day: Date, seconds: TimeInterval)] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let day = LockLog.day(containing: date)
            let seconds = LockLog.lockedSeconds(in: day, sessions: sessions,
                                                liveStart: isLocked ? lockedAt : nil, now: now)
            return (day.start, seconds)
        }
    }

    // MARK: Lifecycle

    /// Called on launch and whenever the app returns to the foreground.
    func refresh() {
        isAuthorized = screenTime.isAuthorized
        // Re-read the Keychain. If it was unreadable at launch (for example
        // iOS started the app before the phone was first unlocked), the tags
        // would otherwise stay missing and a locked phone could not be
        // unlocked by tag. A failed read keeps what is already in memory.
        if let saved = TagStore.loadTags() {
            tags = saved
        }
        if let used = TagStore.emergencyUsed() {
            emergencyUsed = used
        }
        // Shields persist on their own, but re-applying keeps the system
        // state and our saved state from drifting apart.
        if isLocked && isAuthorized, let mode = activeMode {
            screenTime.applyShields(for: mode.selection)
        }
    }

    // MARK: Setup

    func requestAuthorization() async {
        do {
            try await screenTime.requestAuthorization()
        } catch {
            fail("Screen Time access was not granted. Latch cannot block apps without it.")
        }
        isAuthorized = screenTime.isAuthorized
    }

    func pairTag() async {
        guard !isLocked else { return }
        do {
            let uid = try await nfc.scan(prompt: "Hold your iPhone near the tag you want to pair.")
            if tags.contains(where: { $0.id == uid }) {
                fail("That tag is already paired.")
                return
            }
            let updated = tags + [PairedTag(id: uid, name: "Tag \(tags.count + 1)")]
            guard TagStore.saveTags(updated) else {
                // Showing a tag that was never saved would let it vanish on
                // the next launch, possibly while locked.
                fail("Could not save the tag. It was not paired. Try again.")
                return
            }
            tags = updated
            Haptics.success()
        } catch {
            report(error)
        }
    }

    func removeTags(at offsets: IndexSet) {
        guard !isLocked else { return }
        var updated = tags
        updated.remove(atOffsets: offsets)
        guard TagStore.saveTags(updated) else {
            fail("Could not remove the tag. Try again.")
            return
        }
        tags = updated
    }

    // MARK: Modes (only editable while unlocked, so a lock cannot be weakened)

    var canAddMode: Bool { modes.count < Mode.limit }

    @discardableResult
    func addMode(name: String, selection: FamilyActivitySelection) -> Bool {
        guard !isLocked, canAddMode else { return false }
        let mode = Mode(name: cleanName(name), selection: selection)
        modes.append(mode)
        if modes.count == 1 { activeModeID = mode.id }
        saveModes()
        return true
    }

    func updateMode(_ mode: Mode) {
        guard !isLocked, let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        var cleaned = mode
        cleaned.name = cleanName(mode.name)
        modes[index] = cleaned
        saveModes()
    }

    /// There is always at least one mode, so the last one cannot be deleted.
    var canDeleteModes: Bool { !isLocked && modes.count > 1 }

    func deleteModes(at offsets: IndexSet) {
        guard canDeleteModes, offsets.count < modes.count else { return }
        modes.remove(atOffsets: offsets)
        if !modes.contains(where: { $0.id == activeModeID }) {
            activeModeID = modes.first?.id
        }
        saveModes()
    }

    func activate(_ mode: Mode) {
        guard !isLocked, modes.contains(where: { $0.id == mode.id }) else { return }
        activeModeID = mode.id
        saveModes()
    }

    private func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mode \(modes.count + 1)" : String(trimmed.prefix(30))
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
                fail("That tag is not paired with Latch.")
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

    /// Press-and-hold lock, for when the tag is not nearby. Starting is
    /// flexible; stopping still takes a tag (or an emergency unlock).
    func holdToLock() {
        guard !isLocked, isReady else { return }
        lock()
    }

    func emergencyUnlock() {
        guard isLocked, emergencyRemaining > 0 else { return }
        emergencyUsed += 1
        // Unlock even if the counter fails to save: an emergency unlock must
        // never be blocked by a storage error.
        TagStore.setEmergencyUsed(emergencyUsed)
        unlock()
    }

    private func lock() {
        guard let mode = activeMode else { return }
        screenTime.applyShields(for: mode.selection)
        isLocked = true
        lockedAt = Date()
        saveLockState()
        Haptics.success()
    }

    private func unlock() {
        screenTime.clearShields()
        let now = Date()
        sessions = LockLog.append(LockSession(start: lockedAt ?? now, end: now),
                                  to: sessions, defaults: defaults)
        isLocked = false
        lockedAt = nil
        saveLockState()
        Haptics.success()
    }

    // MARK: Persistence

    private func loadModes() {
        if let data = defaults.data(forKey: Keys.modes),
           let saved = try? JSONDecoder().decode([Mode].self, from: data) {
            modes = saved
        } else if let data = defaults.data(forKey: Keys.legacySelection),
                  let legacy = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            // Builds before modes kept one selection. Carry it over so an
            // existing lock keeps blocking the same apps.
            modes = [Mode(name: "Focus", selection: legacy)]
        }
        if modes.isEmpty {
            modes = [Mode(name: "Focus")]
        }
        if let raw = defaults.string(forKey: Keys.activeModeID), let id = UUID(uuidString: raw),
           modes.contains(where: { $0.id == id }) {
            activeModeID = id
        } else {
            activeModeID = modes.first?.id
        }
        saveModes()
    }

    private func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            defaults.set(data, forKey: Keys.modes)
        }
        defaults.set(activeModeID?.uuidString, forKey: Keys.activeModeID)
    }

    private func saveLockState() {
        defaults.set(isLocked, forKey: Keys.isLocked)
        defaults.set(lockedAt, forKey: Keys.lockedAt)
    }

    private func fail(_ text: String) {
        message = text
        Haptics.error()
    }

    private func report(_ error: Error) {
        if case NFCScanError.cancelled = error { return }
        fail(error.localizedDescription)
    }
}
