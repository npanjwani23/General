import FamilyControls
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthorized = false
    @Published private(set) var lock = LockState.unlocked
    @Published var tags: [PairedTag] = []
    @Published var emergencyUsed = 0
    @Published var message: String?
    @Published private(set) var modes: [Mode] = []
    @Published private(set) var activeModeID: UUID?
    @Published private(set) var sessions: [LockSession] = []
    @Published private(set) var schedules: [Schedule] = []
    /// True while an NFC scan is running, so a second tap can't start
    /// another scan on top of it.
    @Published private(set) var isScanning = false

    private let screenTime = ScreenTimeService()
    private let nfc = NFCService()

    init() {
        SharedStore.migrateIfNeeded()
        loadModes()
        lock = SharedStore.loadLockState()
        tags = TagStore.loadTags() ?? []
        // If the counter can't be read, assume only one unlock is left
        // rather than five; refresh() corrects it once the Keychain answers.
        emergencyUsed = TagStore.emergencyUsed() ?? (TagStore.emergencyLimit - 1)
        sessions = LockLog.load()
        schedules = SharedStore.loadSchedules()
        observeExtension()
        refresh()
        if isAuthorized && SharedStore.isAppGroupAvailable {
            ScheduleRegistrar.repairMissing(schedules)
        }
    }

    // MARK: Derived state

    var isLocked: Bool { lock.isLocked }
    var lockedAt: Date? { lock.lockedAt }

    var emergencyRemaining: Int {
        max(0, TagStore.emergencyLimit - emergencyUsed)
    }

    /// The mode picked on the home screen (what a tap or hold will lock).
    var activeMode: Mode? {
        modes.first { $0.id == activeModeID } ?? modes.first
    }

    /// What to show: while locked, the mode actually being enforced (a
    /// schedule may have locked a different one).
    var displayMode: Mode? {
        if isLocked, let id = lock.modeID, let mode = modes.first(where: { $0.id == id }) {
            return mode
        }
        return activeMode
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

    /// "Bedtime schedule · ends 7:00 AM" while a schedule holds the lock.
    var lockCaption: String? {
        guard isLocked, let id = lock.origin?.scheduleID,
              let schedule = schedules.first(where: { $0.id == id }) else { return nil }
        let name = schedule.name.isEmpty ? "Schedule" : schedule.name
        if let end = schedule.windowEnd(containing: Date()) {
            return "\(name) · ends \(end.formatted(date: .omitted, time: .shortened))"
        }
        return name
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

    /// Called on launch, on returning to the foreground, and when the
    /// schedule extension signals a change.
    func refresh() {
        isAuthorized = screenTime.isAuthorized
        // Re-read the Keychain. If it was unreadable at launch (for example
        // iOS started the app before the phone was first unlocked), the tags
        // would otherwise stay missing and a locked phone could not be
        // unlocked by tag. A failed read keeps what is already in memory.
        if let saved = TagStore.loadTags() {
            tags = saved
        }
        SharedStore.hasPairedTag = !tags.isEmpty
        if let used = TagStore.emergencyUsed() {
            emergencyUsed = used
        }
        // End a schedule's lock whose window closed while the phone was off.
        ScheduleEngine.reconcile()
        // The extension may have locked, unlocked or logged a session.
        lock = SharedStore.loadLockState()
        sessions = LockLog.load()
        // Make the system shields match the saved state both ways, so they
        // can never be left up while Clarity says unlocked.
        if isLocked {
            if isAuthorized, let mode = displayMode {
                Shields.apply(mode.selection)
            }
        } else {
            Shields.clear()
        }
    }

    private func observeExtension() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let state = Unmanaged<AppState>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in state.refresh() }
            },
            LockSignal.name, nil, .deliverImmediately)
    }

    // MARK: Setup

    func requestAuthorization() async {
        do {
            try await screenTime.requestAuthorization()
        } catch {
            fail("Screen Time access was not granted. Clarity cannot block apps without it.")
        }
        isAuthorized = screenTime.isAuthorized
    }

    func pairTag() async {
        guard !isLocked, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            // One hold, two reads: the second proves the tag gives the same
            // ID every time.
            let uid = try await nfc.scan(prompt: "Hold your iPhone near the tag you want to pair.", readTwice: true)
            // Phones, bank and transit cards give a new random ID on every
            // tap (4 bytes starting 08). Paired, they would never match again.
            if uid.count == 8 && uid.hasPrefix("08") {
                fail("That card changes its ID on every tap, so it can't unlock Clarity. Use an NFC sticker (NTAG213 or NTAG215).")
                return
            }
            if tags.contains(where: { $0.id == uid }) {
                fail("That tag is already paired.")
                return
            }
            // A schedule may have locked while the scan sheet was up.
            lock = SharedStore.loadLockState()
            guard !isLocked else { return }
            let updated = tags + [PairedTag(id: uid, name: "Tag \(tags.count + 1)")]
            guard TagStore.saveTags(updated) else {
                // Showing a tag that was never saved would let it vanish on
                // the next launch, possibly while locked.
                fail("Could not save the tag. It was not paired. Try again.")
                return
            }
            tags = updated
            SharedStore.hasPairedTag = true
            Haptics.success()
        } catch {
            report(error)
        }
    }

    func removeTags(at offsets: IndexSet) {
        guard !isLocked else { return }
        var updated = tags
        updated.remove(atOffsets: offsets)
        if updated.isEmpty && schedules.contains(where: \.isEnabled) {
            fail("Turn off your schedules before removing your last tag. A schedule could lock with no tag to unlock it.")
            return
        }
        guard TagStore.saveTags(updated) else {
            fail("Could not remove the tag. Try again.")
            return
        }
        tags = updated
        SharedStore.hasPairedTag = !updated.isEmpty
    }

    // MARK: Modes (only editable while unlocked, so a lock cannot be weakened)

    var canAddMode: Bool { modes.count < Mode.limit }

    @discardableResult
    func addMode(name: String, selection: FamilyActivitySelection) -> Bool {
        guard !isLocked, canAddMode, Mode(name: name, selection: selection).problem == nil else { return false }
        let mode = Mode(name: cleanName(name), selection: selection)
        modes.append(mode)
        if modes.count == 1 { activeModeID = mode.id }
        saveModes()
        return true
    }

    func updateMode(_ mode: Mode) {
        guard !isLocked, mode.problem == nil,
              let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
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
        // Point any schedule that used a deleted mode at one that exists.
        if let fallback = modes.first?.id {
            var changed = false
            for index in schedules.indices where !modes.contains(where: { $0.id == schedules[index].modeID }) {
                schedules[index].modeID = fallback
                changed = true
            }
            if changed { SharedStore.saveSchedules(schedules) }
        }
    }

    func activate(_ mode: Mode) {
        guard !isLocked, modes.contains(where: { $0.id == mode.id }) else { return }
        activeModeID = mode.id
        saveModes()
    }

    func modeName(_ id: UUID) -> String {
        modes.first { $0.id == id }?.name ?? "Missing mode"
    }

    private func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mode \(modes.count + 1)" : String(trimmed.prefix(30))
    }

    // MARK: Schedules (only editable while unlocked)

    var canAddSchedule: Bool { schedules.count < Schedule.limit }

    enum ScheduleSaveResult: Equatable {
        case saved
        /// Saved, but iOS refused to run it, so it was turned off.
        case savedOff(String)
        case rejected(String)
    }

    /// Saves a new or edited schedule and registers it with iOS. The caller
    /// shows any reason itself, so it is not lost while a screen closes.
    @discardableResult
    func saveSchedule(_ draft: Schedule) -> ScheduleSaveResult {
        guard !isLocked else { return .rejected("Schedules can't be changed while locked.") }
        if let problem = draft.problem {
            Haptics.error()
            return .rejected(problem)
        }
        var schedule = draft
        schedule.name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        if !modes.contains(where: { $0.id == schedule.modeID }), let fallback = activeMode?.id {
            schedule.modeID = fallback
        }
        if schedule.isEnabled {
            if !SharedStore.isAppGroupAvailable {
                Haptics.error()
                return .rejected("Schedules need the App Groups capability on both Clarity targets. See the README.")
            }
            if tags.isEmpty {
                Haptics.error()
                return .rejected("Pair a tag first. A schedule must never lock a phone with no tag to unlock it.")
            }
            if let mode = modes.first(where: { $0.id == schedule.modeID }), mode.itemCount == 0 {
                Haptics.error()
                return .rejected("\(mode.name) doesn't block anything yet, so this schedule would never lock. Choose apps for it first.")
            }
        }
        let isNew = !schedules.contains(where: { $0.id == schedule.id })
        if isNew && !canAddSchedule {
            Haptics.error()
            return .rejected("You can have up to \(Schedule.limit) schedules.")
        }

        var result = ScheduleSaveResult.saved
        do {
            try ScheduleRegistrar.register(schedule)
        } catch {
            // Keep what was typed, but off, so nothing half-works.
            schedule.isEnabled = false
            result = .savedOff(error.localizedDescription)
            Haptics.error()
        }

        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        SharedStore.saveSchedules(schedules)
        return result
    }

    @discardableResult
    func setScheduleEnabled(_ id: UUID, _ enabled: Bool) -> ScheduleSaveResult {
        guard var schedule = schedules.first(where: { $0.id == id }) else {
            return .rejected("That schedule no longer exists.")
        }
        schedule.isEnabled = enabled
        return saveSchedule(schedule)
    }

    func deleteSchedules(at offsets: IndexSet) {
        guard !isLocked else { return }
        for index in offsets {
            ScheduleRegistrar.stop(schedules[index].id)
        }
        schedules.remove(atOffsets: offsets)
        SharedStore.saveSchedules(schedules)
    }

    // MARK: Lock and unlock

    /// Scans a tag. A paired tag toggles the lock, anything else is rejected.
    func tapTag() async {
        guard isLocked || isReady, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        // Remember what this tap is for. A schedule can lock or unlock while
        // the scan sheet is up; the scan must not then do the opposite.
        let wantsLock = !isLocked
        do {
            let prompt = isLocked
                ? "Hold your iPhone near your tag to unlock."
                : "Hold your iPhone near your tag to lock."
            let uid = try await nfc.scan(prompt: prompt)
            guard tags.contains(where: { $0.id == uid }) else {
                fail("That tag is not paired with Clarity.")
                return
            }
            lock = SharedStore.loadLockState()
            if wantsLock {
                if !isLocked && isReady { startLock(origin: .tag) }
            } else {
                if isLocked { endLock() }
            }
        } catch {
            report(error)
        }
    }

    /// Press-and-hold lock, for when the tag is not nearby. Starting is
    /// flexible; stopping still takes a tag (or an emergency unlock).
    func holdToLock() {
        lock = SharedStore.loadLockState()
        guard !isLocked, isReady, !isScanning else { return }
        startLock(origin: .hold)
    }

    func emergencyUnlock() {
        guard isLocked else { return }
        // Count from the stored value too, so a stale in-memory number can
        // never write a lower count over a higher one.
        let current = max(emergencyUsed, TagStore.emergencyUsed() ?? emergencyUsed)
        guard current < TagStore.emergencyLimit else {
            emergencyUsed = current
            return
        }
        emergencyUsed = current + 1
        // Unlock even if the counter fails to save: an emergency unlock must
        // never be blocked by a storage error.
        TagStore.setEmergencyUsed(emergencyUsed)
        endLock()
    }

    private func startLock(origin: LockOrigin) {
        guard let mode = activeMode, mode.problem == nil else { return }
        lock = LockState(isLocked: true, lockedAt: Date(), origin: origin, modeID: mode.id)
        SharedStore.saveLockState(lock)
        Shields.apply(mode.selection)
        Haptics.success()
    }

    private func endLock() {
        let now = Date()
        // Unlocking during a schedule's window ends that window for today,
        // so the schedule does not lock again until its next window.
        for schedule in schedules {
            if let end = schedule.windowEnd(containing: now) {
                SharedStore.dismiss(schedule.id, until: end)
            }
        }
        let started = lockedAt ?? now
        lock = .unlocked
        SharedStore.saveLockState(lock)
        Shields.clear()
        sessions = LockLog.append(LockSession(start: started, end: now))
        Haptics.success()
    }

    // MARK: Persistence

    private func loadModes() {
        modes = SharedStore.loadModes()
        if modes.isEmpty,
           let data = SharedStore.defaults.data(forKey: SharedStore.Key.legacySelection),
           let legacy = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            // Builds before modes kept one selection. Carry it over so an
            // existing lock keeps blocking the same apps.
            modes = [Mode(name: "Focus", selection: legacy)]
        }
        if modes.isEmpty {
            modes = [Mode(name: "Focus")]
        }
        if let id = SharedStore.activeModeID, modes.contains(where: { $0.id == id }) {
            activeModeID = id
        } else {
            activeModeID = modes.first?.id
        }
        // A lock from before modes existed has no mode id; tie it to the
        // migrated mode so the home screen shows what is being enforced.
        var state = SharedStore.loadLockState()
        if state.isLocked && (state.modeID == nil || state.lockedAt == nil) {
            state.modeID = state.modeID ?? activeModeID
            // Without a start time the timer and stats can't work.
            state.lockedAt = state.lockedAt ?? Date()
            SharedStore.saveLockState(state)
        }
        saveModes()
    }

    private func saveModes() {
        SharedStore.saveModes(modes, activeID: activeModeID)
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
