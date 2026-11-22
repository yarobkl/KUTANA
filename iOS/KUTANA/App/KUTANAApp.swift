import SwiftUI
import UserNotifications

final class KutanaNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = KutanaNotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct KUTANAApp: App {
    @StateObject private var identity = KutanaSessionStore()
    @Environment(\.scenePhase) private var scenePhase
    init() { UNUserNotificationCenter.current().delegate = KutanaNotificationPresenter.shared }
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
