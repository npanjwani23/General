import SwiftUI

@main
struct LatchApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(state)
                // Light while unlocked, dark while locked: the state shows
                // at a glance before reading anything.
                .preferredColorScheme(state.isLocked ? .dark : .light)
                .tint(.orange)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                state.refresh()
            }
        }
    }
}
