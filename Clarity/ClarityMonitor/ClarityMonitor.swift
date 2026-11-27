import DeviceActivity
import Foundation

/// iOS wakes this extension at the start and end of each scheduled window,
/// even when Clarity is not running. All decisions live in ScheduleEngine.
final class ClarityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let id = Schedule.id(fromActivity: activity.rawValue) else { return }
        ScheduleEngine.intervalDidStart(id)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let id = Schedule.id(fromActivity: activity.rawValue) else { return }
        ScheduleEngine.intervalDidEnd(id)
    }
}
