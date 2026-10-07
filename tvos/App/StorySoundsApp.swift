import SwiftUI
import StorySoundsCore

@main
struct StorySoundsApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("Story Sounds").font(.largeTitle)
            Button("Start") {}.accessibilityIdentifier("start")
        }
    }
}
