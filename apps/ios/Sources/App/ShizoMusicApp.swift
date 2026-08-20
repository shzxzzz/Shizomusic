import SwiftUI
import UIKit

@MainActor
final class ShizoMusicAppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundSessionCompletion: (() -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Self.backgroundSessionCompletion = completionHandler
    }
}

@main
struct ShizoMusicApp: App {
    @UIApplicationDelegateAdaptor(ShizoMusicAppDelegate.self) private var appDelegate
    @StateObject private var authorization = AuthorizationStore()

    var body: some Scene {
        WindowGroup {
            AuthorizationRootView()
                .environmentObject(authorization)
        }
    }
}
