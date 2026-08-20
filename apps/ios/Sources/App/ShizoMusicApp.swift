import SwiftUI

@main
struct ShizoMusicApp: App {
    @StateObject private var authorization = AuthorizationStore()

    var body: some Scene {
        WindowGroup {
            AuthorizationRootView()
                .environmentObject(authorization)
        }
    }
}
