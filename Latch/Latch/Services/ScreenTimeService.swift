import FamilyControls
import ManagedSettings

/// Wraps Apple's Screen Time APIs. Shields set here are enforced by iOS itself,
/// so they survive the app being killed and the phone rebooting.
@MainActor
final class ScreenTimeService {
    private let store = ManagedSettingsStore()

    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func applyShields(for selection: FamilyActivitySelection) {
        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let domains = selection.webDomainTokens

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = domains.isEmpty ? nil : domains
        if categories.isEmpty {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        } else {
            store.shield.applicationCategories = .specific(categories)
            store.shield.webDomainCategories = .specific(categories)
        }

        // Stops the escape hatch of deleting Latch (or any app) mid-session.
        store.application.denyAppRemoval = true
    }

    func clearShields() {
        store.clearAllSettings()
    }
}
