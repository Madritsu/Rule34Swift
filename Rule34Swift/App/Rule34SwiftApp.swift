import SwiftUI

@main
struct Rule34SwiftApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView(settings: settings)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #else
        WindowGroup {
            ContentView(settings: settings)
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
