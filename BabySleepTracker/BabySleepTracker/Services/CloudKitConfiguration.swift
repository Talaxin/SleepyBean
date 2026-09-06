import Foundation

enum CloudKitConfiguration {
    static let containerIdentifier = "iCloud.com.sleepybean.tracker"

    /// CloudKit sync requires a properly signed build with the CloudKit entitlement.
    /// Feather/sideload builds fall back to local-only storage.
    static var isCloudKitAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
