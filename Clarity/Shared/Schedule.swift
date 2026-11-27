import Foundation

/// Locks a mode automatically between two times on chosen days, for example
/// "Bedtime, every day, 10:30 PM to 7:00 AM". Unlocking early still takes a
/// tag (or an emergency unlock); a schedule never unlocks a lock it did not
/// start.
struct Schedule: Codable, Identifiable, Equatable {
    static let limit = 10
    /// Apple's monitor will not run an interval shorter than 15 minutes.
    static let minimumMinutes = 15
    static let dayMinutes = 24 * 60

    let id: UUID
    var name: String
    var modeID: UUID
    /// Minutes after midnight, 0..<1440.
    var startMinutes: Int
    var endMinutes: Int
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday. For overnight windows
    /// this is the day the window starts.
    var weekdays: Set<Int>
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, modeID: UUID, startMinutes: Int = 22 * 60,
         endMinutes: Int = 7 * 60, weekdays: Set<Int> = Set(1...7), isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.modeID = modeID
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    /// An end of 12:00 AM means "until midnight", not an overnight window.
    var endsAtMidnight: Bool { endMinutes == 0 && startMinutes != 0 }

    /// End in minutes after the start day's midnight (1440 for midnight).
    var effectiveEnd: Int { endsAtMidnight ? Self.dayMinutes : endMinutes }

    var crossesMidnight: Bool { !endsAtMidnight && endMinutes < startMinutes }

    var durationMinutes: Int {
        crossesMidnight ? Self.dayMinutes - startMinutes + endMinutes : effectiveEnd - startMinutes
    }

    /// Windows closer than this to the next one would never be seen to end,
    /// because window edges are read with a minute of slack.
    static let minimumGapMinutes = 5

    // MARK: Validation

    /// Why this schedule cannot be saved, or nil if it is fine.
    var problem: String? {
        if weekdays.isEmpty { return "Pick at least one day." }
        if startMinutes == endMinutes { return "Start and end can't be the same time." }
        if durationMinutes < Self.minimumMinutes {
            return "A schedule has to last at least \(Self.minimumMinutes) minutes."
        }
        if Self.dayMinutes - durationMinutes < Self.minimumGapMinutes {
            return "Leave at least \(Self.minimumGapMinutes) minutes between the end and the next start."
        }
        if crossesMidnight {
            // Overnight windows run as two pieces (to midnight, from
            // midnight), and each piece must also meet the 15 minute floor.
            // The night piece ends at 11:59:59 PM, so leave headroom.
            if startMinutes > Self.dayMinutes - 30 {
                return "Overnight schedules need to start by 11:30 PM."
            }
            if endMinutes < Self.minimumMinutes {
                return "Overnight schedules need to end at 12:15 AM or later."
            }
        }
        return nil
    }

    // MARK: Monitor activity names

    /// One activity for a same-day window; two ("night", "morning") for a
    /// window that crosses midnight.
    var activityNames: [String] {
        crossesMidnight
            ? ["schedule.\(id.uuidString).night", "schedule.\(id.uuidString).morning"]
            : ["schedule.\(id.uuidString)"]
    }

    static func allActivityNames(for id: UUID) -> [String] {
        ["schedule.\(id.uuidString)", "schedule.\(id.uuidString).night", "schedule.\(id.uuidString).morning"]
    }

    static func id(fromActivity raw: String) -> UUID? {
        let parts = raw.split(separator: ".")
        guard parts.count >= 2, parts[0] == "schedule" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    // MARK: Time math

    /// True when `date` falls inside one of this schedule's windows.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else { return false }
        let now = hour * 60 + minute
        if !crossesMidnight {
            return weekdays.contains(weekday) && now >= startMinutes && now < effectiveEnd
        }
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (now >= startMinutes && weekdays.contains(weekday))
            || (now < endMinutes && weekdays.contains(yesterday))
    }

    /// When the window containing `date` ends. Nil if `date` is outside.
    func windowEnd(containing date: Date, calendar: Calendar = .current) -> Date? {
        guard contains(date, calendar: calendar) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let startOfDay = calendar.startOfDay(for: date)
        let endsTomorrow = (crossesMidnight && now >= startMinutes) || endsAtMidnight
        guard let day = calendar.date(byAdding: .day, value: endsTomorrow ? 1 : 0, to: startOfDay) else { return nil }
        if endsAtMidnight { return day }
        // Set the wall-clock time rather than adding minutes to midnight, so
        // the end stays right on daylight-saving days.
        return calendar.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: day)
    }

    // MARK: Display

    var timeText: String {
        "\(Self.clockText(startMinutes)) – \(Self.clockText(endMinutes))"
    }

    var daysText: String {
        switch weekdays {
        case Set(1...7): return "Every day"
        case Set(2...6): return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return weekdays.sorted { Self.mondayFirst($0) < Self.mondayFirst($1) }
                .map { symbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }

    /// Sort key that puts Monday first, which reads more naturally.
    static func mondayFirst(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    static func clockText(_ minutes: Int) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar.current.date(from: parts) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
