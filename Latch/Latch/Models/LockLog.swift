import Foundation

/// One finished lock session.
struct LockSession: Codable, Equatable {
    let start: Date
    let end: Date
}

/// History of finished lock sessions, used for "time locked today" and the
/// weekly view. Kept on the phone only and trimmed to the last 60 days.
enum LockLog {
    private static let key = "lockSessions"
    private static let keepDays = 60

    static func load(_ defaults: UserDefaults = .standard) -> [LockSession] {
        guard let data = defaults.data(forKey: key),
              let sessions = try? JSONDecoder().decode([LockSession].self, from: data) else {
            return []
        }
        return sessions
    }

    static func append(_ session: LockSession, to sessions: [LockSession],
                       defaults: UserDefaults = .standard) -> [LockSession] {
        guard session.end > session.start else { return sessions }
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? .distantPast
        let updated = (sessions + [session]).filter { $0.end >= cutoff }
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: key)
        }
        return updated
    }

    /// Seconds locked inside `interval`, counting the live session (if any)
    /// up to `now`. Sessions that cross midnight are split between days.
    static func lockedSeconds(in interval: DateInterval, sessions: [LockSession],
                              liveStart: Date?, now: Date = Date()) -> TimeInterval {
        var spans = sessions.map { DateInterval(start: $0.start, end: $0.end) }
        if let liveStart, now > liveStart {
            spans.append(DateInterval(start: liveStart, end: now))
        }
        return spans.reduce(0) { total, span in
            total + (span.intersection(with: interval)?.duration ?? 0)
        }
    }

    /// Calendar day containing `date`.
    static func day(containing date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 86_400)
    }
}

enum DurationText {
    /// "2h 30m", "45m", "0m".
    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// "0h 12m 03s" for the live lock timer.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%dh %02dm %02ds", total / 3600, (total % 3600) / 60, total % 60)
    }
}
