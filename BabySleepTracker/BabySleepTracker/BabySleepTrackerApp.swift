import SwiftUI
import SwiftData
import CloudKit

@main
struct BabySleepTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer = SleepyBeanModelContainer.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { @MainActor in
                        await CloudKitSharingCoordinator.shared.acceptShare(from: url)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { @MainActor in
                        await CloudKitSharingCoordinator.shared.acceptShare(from: url)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
