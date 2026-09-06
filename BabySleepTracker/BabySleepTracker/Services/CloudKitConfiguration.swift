import CloudKit
import Foundation

enum CloudKitConfiguration {
    static let containerIdentifier = "iCloud.com.sleepybean.tracker"

    /// CloudKit uses the iCloud account, not iCloud Drive. Drive being off
    /// used to make `ubiquityIdentityToken` nil and force local-only storage.
    static var isCloudKitAvailable: Bool {
        true
    }
}

@MainActor
@Observable
final class iCloudAccountMonitor {
    static let shared = iCloudAccountMonitor()

    var status: CKAccountStatus = .couldNotDetermine

    var isSignedIn: Bool {
        status == .available
    }

    var statusText: String {
        switch status {
        case .available:
            return "Signed in to iCloud"
        case .noAccount:
            return "Not signed in to iCloud"
        case .restricted:
            return "iCloud is restricted on this device"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .couldNotDetermine:
            return "Checking iCloud…"
        @unknown default:
            return "Checking iCloud…"
        }
    }

    func refresh() async {
        do {
            status = try await CKContainer(identifier: CloudKitConfiguration.containerIdentifier).accountStatus()
        } catch {
            status = .couldNotDetermine
        }
    }
}
