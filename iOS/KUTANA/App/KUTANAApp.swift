import SwiftUI

@main
struct KUTANAApp: App {
    @StateObject private var identity = KutanaSessionStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WelcomeFlow()
                .environmentObject(identity)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await identity.restore() } }
                }
        }
    }
}
