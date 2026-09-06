import Foundation
import SwiftData

enum SleepyBeanModelContainer {
    private(set) static var isCloudKitEnabled = false
    private(set) static var storeURL: URL?

    static func make() -> ModelContainer {
        let schema = Schema([BabyProfile.self, SleepSession.self, FeedEntry.self])

        if CloudKitConfiguration.isCloudKitAvailable {
            do {
                let configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(CloudKitConfiguration.containerIdentifier)
                )
                let container = try ModelContainer(for: schema, configurations: configuration)
                isCloudKitEnabled = true
                storeURL = configuration.url
                return container
            } catch {
                print("CloudKit ModelContainer failed, using local storage: \(error.localizedDescription)")
            }
        }

        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            isCloudKitEnabled = false
            storeURL = configuration.url
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
