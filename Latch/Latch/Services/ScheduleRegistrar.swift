import DeviceActivity
import Foundation

/// Tells iOS which schedule windows to watch. Each schedule is registered
/// on its own, so saving one never restarts (and re-fires) the others.
enum ScheduleRegistrar {
    enum Failure: LocalizedError {
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .rejected(let reason): return "iOS would not set up this schedule. \(reason)"
            }
        }
    }

    static func register(_ schedule: Schedule) throws {
        let center = DeviceActivityCenter()
        stop(schedule.id, center: center)
        guard schedule.isEnabled else { return }

        let pieces: [(name: String, start: DateComponents, end: DateComponents)]
        if schedule.crossesMidnight {
            pieces = [
                (schedule.activityNames[0], components(schedule.startMinutes), DateComponents(hour: 23, minute: 59, second: 59)),
                (schedule.activityNames[1], DateComponents(hour: 0, minute: 0), components(schedule.endMinutes)),
            ]
        } else {
            let end = schedule.endsAtMidnight
                ? DateComponents(hour: 23, minute: 59, second: 59)
                : components(schedule.endMinutes)
            pieces = [(schedule.activityNames[0], components(schedule.startMinutes), end)]
        }

        do {
            for piece in pieces {
                try center.startMonitoring(
                    DeviceActivityName(piece.name),
                    during: DeviceActivitySchedule(intervalStart: piece.start, intervalEnd: piece.end, repeats: true)
                )
            }
        } catch {
            // Do not leave half of an overnight schedule running.
            stop(schedule.id, center: center)
            throw Failure.rejected(error.localizedDescription)
        }
    }

    /// Re-registers enabled schedules iOS is no longer watching (for example
    /// after a backup restore, or after Screen Time access was granted
    /// again). Schedules still being watched are left untouched, so this
    /// never re-fires a window that is already running.
    static func repairMissing(_ schedules: [Schedule]) {
        let watched = Set(DeviceActivityCenter().activities.map(\.rawValue))
        for schedule in schedules where schedule.isEnabled {
            if !schedule.activityNames.allSatisfy(watched.contains) {
                try? register(schedule)
            }
        }
    }

    static func stop(_ id: UUID, center: DeviceActivityCenter = DeviceActivityCenter()) {
        center.stopMonitoring(Schedule.allActivityNames(for: id).map { DeviceActivityName($0) })
    }

    private static func components(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }
}
