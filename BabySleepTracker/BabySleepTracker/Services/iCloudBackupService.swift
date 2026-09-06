import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum iCloudBackupError: LocalizedError {
    case notSignedIn
    case containerUnavailable
    case missingBackup
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to iCloud on this iPhone, then return to SleepyBean."
        case .containerUnavailable:
            return "iCloud Drive is not available for this install. Use Export to Files below and save the backup to iCloud Drive, or re-sign SleepyBean in Feather with iCloud enabled."
        case .missingBackup:
            return "No SleepyBean backup was found in iCloud."
        case .invalidBackup:
            return "The backup file could not be read."
        }
    }
}

enum iCloudAccountStatus: Equatable {
    case notSignedIn
    case signedInNoContainer
    case ready

    var label: String {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .signedInNoContainer: return "Drive unavailable"
        case .ready: return "Ready"
        }
    }

    var isPositive: Bool {
        self == .ready
    }
}

@MainActor
@Observable
final class iCloudBackupService {
    static let shared = iCloudBackupService()

    private let containerIdentifier = "iCloud.com.sleepybean.tracker"
    private let backupFileName = "SleepyBeanBackup.json"
    private let lastBackupKey = "sleepybean.lastICloudBackupDate"
    private let lastLocalBackupKey = "sleepybean.lastLocalBackupDate"

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    var lastLocalBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastLocalBackupKey) as? Date
    }

    var isSignedInToiCloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var isContainerAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) != nil
    }

    var accountStatus: iCloudAccountStatus {
        if !isSignedInToiCloud {
            return .notSignedIn
        }
        if !isContainerAvailable {
            return .signedInNoContainer
        }
        return .ready
    }

    private var iCloudBackupFileURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent(backupFileName, isDirectory: false)
    }

    var localBackupFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(backupFileName, isDirectory: false)
    }

    func makeBackupData(context: ModelContext) throws -> Data {
        let babies = try context.fetch(FetchDescriptor<BabyProfile>())
        let backup = SleepyBeanBackupEncoder.makeBackup(from: babies)
        return try JSONEncoder().encode(backup)
    }

    func restoreBackupData(_ data: Data, context: ModelContext) throws {
        let backup = try JSONDecoder().decode(SleepyBeanBackupFile.self, from: data)
        try SleepyBeanBackupEncoder.restore(backup, into: context)
    }

    func backup(context: ModelContext) async throws {
        guard isSignedInToiCloud else { throw iCloudBackupError.notSignedIn }
        guard let fileURL = iCloudBackupFileURL else { throw iCloudBackupError.containerUnavailable }

        let data = try makeBackupData(context: context)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    func restore(context: ModelContext) async throws {
        guard isSignedInToiCloud else { throw iCloudBackupError.notSignedIn }
        guard let fileURL = iCloudBackupFileURL else { throw iCloudBackupError.containerUnavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw iCloudBackupError.missingBackup }

        let data = try Data(contentsOf: fileURL)
        try restoreBackupData(data, context: context)
    }

    func saveLocalBackup(context: ModelContext) throws {
        let data = try makeBackupData(context: context)
        try data.write(to: localBackupFileURL, options: .atomic)
        UserDefaults.standard.set(Date(), forKey: lastLocalBackupKey)
    }

    func backupIfPossible(context: ModelContext) async {
        guard AppPreferences.iCloudBackupEnabled else { return }

        if accountStatus == .ready {
            do {
                try await backup(context: context)
                return
            } catch {
                print("iCloud backup failed: \(error.localizedDescription)")
            }
        }

        do {
            try saveLocalBackup(context: context)
        } catch {
            print("Local backup failed: \(error.localizedDescription)")
        }
    }
}

struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw iCloudBackupError.invalidBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
