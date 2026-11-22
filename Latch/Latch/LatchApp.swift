import SwiftUI

@main
struct LatchApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                state.refresh()
            }
        }
    }
}
