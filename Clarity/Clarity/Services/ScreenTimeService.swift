import FamilyControls

/// Screen Time permission. Shields themselves live in `Shields` (shared with
/// the schedule extension).
@MainActor
final class ScreenTimeService {
    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}
