import Foundation

/// What happens when a schedule's window opens or closes. Runs inside the
/// monitor extension (no UI), so every decision reads fresh shared state.
///
/// Rules:
/// - A schedule only locks if nothing else is locked, it is on, today is one
///   of its days, and you have not already unlocked it early this window.
/// - A schedule only unlocks a lock it started. A lock from your tag or a
///   hold is left alone.
/// - If another schedule's window is still open when one ends, the lock is
///   handed to it instead of dropping.
enum ScheduleEngine {
    /// Callbacks can land a moment early or late; this much slack keeps a
    /// window edge from being misread.
    private static let slack: TimeInterval = 60

    static func intervalDidStart(_ id: UUID, now: Date = Date()) {
        let schedules = SharedStore.loadSchedules()
        guard let schedule = schedules.first(where: { $0.id == id }), schedule.isEnabled else { return }
        guard schedule.contains(now) || schedule.contains(now.addingTimeInterval(slack)) else { return }
        if let until = SharedStore.dismissedUntil(id), until > now { return }

        let state = SharedStore.loadLockState()
        guard !state.isLocked else { return }
        // Never lock a phone that has no tag to unlock it with.
        guard SharedStore.hasPairedTag else { return }
        guard let mode = SharedStore.loadModes().first(where: { $0.id == schedule.modeID }),
              mode.itemCount > 0, mode.problem == nil else { return }

        // Save first: if iOS kills the extension between the two steps, the
        // app sees "locked" and re-applies the shields, rather than shields
        // being up while the app says "unlocked".
        SharedStore.saveLockState(LockState(isLocked: true, lockedAt: now,
                                            origin: .schedule(id), modeID: mode.id))
        Shields.apply(mode.selection)
        LockSignal.post()
    }

    static func intervalDidEnd(_ id: UUID, now: Date = Date()) {
        var state = SharedStore.loadLockState()
        guard state.isLocked, state.origin == .schedule(id) else { return }

        let schedules = SharedStore.loadSchedules()
        // The night piece of an overnight window ends at 11:59:59 PM while
        // the window carries on past midnight: keep the lock.
        if let schedule = schedules.first(where: { $0.id == id }),
           schedule.isEnabled, schedule.contains(now.addingTimeInterval(slack)) {
            return
        }

        // Hand over to another schedule that is still inside its window.
        let modes = SharedStore.loadModes()
        for next in schedules where next.id != id && next.isEnabled && next.contains(now.addingTimeInterval(slack)) {
            if let until = SharedStore.dismissedUntil(next.id), until > now { continue }
            guard let mode = modes.first(where: { $0.id == next.modeID }),
                  mode.itemCount > 0, mode.problem == nil else { continue }
            state.origin = .schedule(next.id)
            state.modeID = mode.id
            SharedStore.saveLockState(state)
            Shields.apply(mode.selection)
            LockSignal.post()
            return
        }

        SharedStore.saveLockState(.unlocked)
        Shields.clear()
        LockLog.append(LockSession(start: state.lockedAt ?? now, end: now))
        LockSignal.post()
    }

    /// Ends a schedule's lock whose window is over but whose end callback
    /// never arrived (phone off at the time, extension killed). The clock
    /// can't be moved while locked, so this can't be used to cheat.
    static func reconcile(now: Date = Date()) {
        let state = SharedStore.loadLockState()
        guard state.isLocked, let id = state.origin?.scheduleID else { return }
        let schedule = SharedStore.loadSchedules().first { $0.id == id }
        if let schedule, schedule.isEnabled, schedule.contains(now) { return }
        intervalDidEnd(id, now: now)
    }
}
