import Foundation
import SwiftData

enum iCloudBackupError: LocalizedError {
    case unavailable
    case missingBackup
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "iCloud is not available. Sign in to iCloud in Settings and enable iCloud Drive."
        case .missingBackup:
            return "No SleepyBean backup was found in iCloud."
        case .invalidBackup:
            return "The iCloud backup file could not be read."
        }
    }
}

@MainActor
@Observable
final class iCloudBackupService {
    static let shared = iCloudBackupService()

    private let containerIdentifier = "iCloud.com.sleepybean.tracker"
    private let backupFileName = "SleepyBeanBackup.json"
    private let lastBackupKey = "sleepybean.lastICloudBackupDate"

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    var isSignedInToiCloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var backupFileURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent(backupFileName, isDirectory: false)
    }

    func backup(context: ModelContext) async throws {
        guard isSignedInToiCloud else {
            throw iCloudBackupError.unavailable
        }

        let babies = try context.fetch(FetchDescriptor<BabyProfile>())
        let backup = SleepyBeanBackupEncoder.makeBackup(from: babies)
        let data = try JSONEncoder().encode(backup)

        guard let fileURL = backupFileURL else {
            throw iCloudBackupError.unavailable
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    func restore(context: ModelContext) async throws {
        guard isSignedInToiCloud else {
            throw iCloudBackupError.unavailable
        }

        guard let fileURL = backupFileURL else {
            throw iCloudBackupError.unavailable
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw iCloudBackupError.missingBackup
        }

        let data = try Data(contentsOf: fileURL)
        let backup = try JSONDecoder().decode(SleepyBeanBackupFile.self, from: data)
        try SleepyBeanBackupEncoder.restore(backup, into: context)
    }

    func backupIfPossible(context: ModelContext) async {
        do {
            try await backup(context: context)
        } catch {
            print("Automatic iCloud backup skipped: \(error.localizedDescription)")
        }
    }
}
