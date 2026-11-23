import FamilyControls
import ManagedSettings

/// Applies and clears the system shields. The app and the schedule extension
/// share the same default store, so a lock set by one is visible to the other.
/// iOS enforces the shields itself, so they survive Latch being killed and
/// the phone rebooting.
enum Shields {
    static func apply(_ selection: FamilyActivitySelection) {
        let store = ManagedSettingsStore()
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

        // Stops the escape hatch of deleting Latch (or any app) mid-lock.
        store.application.denyAppRemoval = true
        // Stops ending a scheduled lock early by moving the clock past the
        // window's end. Cleared again by clear().
        store.dateAndTime.requireAutomaticDateAndTime = true
    }

    static func clear() {
        ManagedSettingsStore().clearAllSettings()
    }
}
