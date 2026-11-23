import Foundation

/// Who started the current lock. Only a schedule's own lock is ended by
/// that schedule; a lock you started yourself is never ended by a schedule.
enum LockOrigin: Equatable {
    case tag
    case hold
    case schedule(UUID)

    init?(raw: String?) {
        guard let raw else { return nil }
        switch raw {
        case "tag": self = .tag
        case "hold": self = .hold
        default:
            guard raw.hasPrefix("schedule:"),
                  let id = UUID(uuidString: String(raw.dropFirst("schedule:".count))) else { return nil }
            self = .schedule(id)
        }
    }

    var raw: String {
        switch self {
        case .tag: return "tag"
        case .hold: return "hold"
        case .schedule(let id): return "schedule:\(id.uuidString)"
        }
    }

    var scheduleID: UUID? {
        if case .schedule(let id) = self { return id }
        return nil
    }
}

struct LockState: Equatable {
    var isLocked = false
    var lockedAt: Date?
    var origin: LockOrigin?
    /// The mode being enforced. A schedule can lock a mode that is not the
    /// one picked on the home screen.
    var modeID: UUID?

    static let unlocked = LockState()
}

/// Settings and lock state shared by the app and the schedule extension,
/// kept in the app group so both processes read the same values.
enum SharedStore {
    static let appGroup = "group.app.latch.personal"

    /// Falls back to the app's own defaults if the app group is missing
    /// (unsigned builds), which keeps the app working without schedules.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    enum Key {
        static let modes = "modes"
        static let activeModeID = "activeModeID"
        static let isLocked = "isLocked"
        static let lockedAt = "lockedAt"
        static let lockOrigin = "lockOrigin"
        static let lockedModeID = "lockedModeID"
        static let sessions = "lockSessions"
        static let schedules = "schedules"
        static let dismissed = "scheduleDismissedUntil"
        static let legacySelection = "selection"
        static let migrated = "migratedToAppGroup"
        static let hasPairedTag = "hasPairedTag"
    }

    /// False when this build is not entitled to the app group. Then the app
    /// and the extension would quietly use separate storage and schedules
    /// would never fire, so the app warns and turns schedules off.
    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    /// Paired tags live in the app's Keychain, which the extension can't
    /// read. The app mirrors "is any tag paired" here so a schedule never
    /// locks a phone that has no tag to unlock it with.
    static var hasPairedTag: Bool {
        get { defaults.bool(forKey: Key.hasPairedTag) }
        set { defaults.set(newValue, forKey: Key.hasPairedTag) }
    }

    /// Builds before schedules kept everything in the app's own defaults.
    /// Copy it into the app group once so an existing lock survives.
    static func migrateIfNeeded() {
        guard defaults !== UserDefaults.standard, !defaults.bool(forKey: Key.migrated) else { return }
        let old = UserDefaults.standard
        for key in [Key.modes, Key.activeModeID, Key.isLocked, Key.lockedAt,
                    Key.sessions, Key.legacySelection] where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: Key.migrated)
    }

    // MARK: Modes

    static func loadModes() -> [Mode] {
        guard let data = defaults.data(forKey: Key.modes),
              let modes = try? JSONDecoder().decode([Mode].self, from: data) else { return [] }
        return modes
    }

    static func saveModes(_ modes: [Mode], activeID: UUID?) {
        if let data = try? JSONEncoder().encode(modes) {
            defaults.set(data, forKey: Key.modes)
        }
        defaults.set(activeID?.uuidString, forKey: Key.activeModeID)
    }

    static var activeModeID: UUID? {
        defaults.string(forKey: Key.activeModeID).flatMap(UUID.init(uuidString:))
    }

    // MARK: Lock state

    static func loadLockState() -> LockState {
        let locked = defaults.bool(forKey: Key.isLocked)
        guard locked else { return .unlocked }
        return LockState(
            isLocked: true,
            lockedAt: defaults.object(forKey: Key.lockedAt) as? Date,
            origin: LockOrigin(raw: defaults.string(forKey: Key.lockOrigin)),
            modeID: defaults.string(forKey: Key.lockedModeID).flatMap(UUID.init(uuidString:))
        )
    }

    static func saveLockState(_ state: LockState) {
        defaults.set(state.isLocked, forKey: Key.isLocked)
        defaults.set(state.lockedAt, forKey: Key.lockedAt)
        defaults.set(state.origin?.raw, forKey: Key.lockOrigin)
        defaults.set(state.modeID?.uuidString, forKey: Key.lockedModeID)
    }

    // MARK: Schedules

    static func loadSchedules() -> [Schedule] {
        guard let data = defaults.data(forKey: Key.schedules),
              let schedules = try? JSONDecoder().decode([Schedule].self, from: data) else { return [] }
        return schedules
    }

    static func saveSchedules(_ schedules: [Schedule]) {
        if let data = try? JSONEncoder().encode(schedules) {
            defaults.set(data, forKey: Key.schedules)
        }
    }

    /// A schedule you unlocked early stays off until its window ends, so it
    /// does not lock you again a minute later.
    static func dismissedUntil(_ id: UUID) -> Date? {
        let map = defaults.dictionary(forKey: Key.dismissed) as? [String: Date] ?? [:]
        return map[id.uuidString]
    }

    static func dismiss(_ id: UUID, until end: Date) {
        var map = defaults.dictionary(forKey: Key.dismissed) as? [String: Date] ?? [:]
        let now = Date()
        map = map.filter { $0.value > now }
        map[id.uuidString] = end
        defaults.set(map, forKey: Key.dismissed)
    }
}

/// Darwin notification so the app redraws when the extension changes the
/// lock while the app is open.
enum LockSignal {
    static let name = "app.latch.personal.lockStateChanged" as CFString

    static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name), nil, nil, true)
    }
}
