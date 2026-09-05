import SwiftUI
import SwiftData

@main
struct BabySleepTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [BabyProfile.self, SleepSession.self, FeedEntry.self])
    }
}
