import SwiftUI
import StorySoundsCore

@main
struct StorySoundsApp: App {
    @StateObject private var host = EnvironmentHost()

    var body: some Scene {
        WindowGroup {
            RootView(host: host)
        }
    }
}
