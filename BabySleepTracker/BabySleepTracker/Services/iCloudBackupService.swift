import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "The backup file could not be read."
        }
    }
}

@MainActor
@Observable
final class iCloudBackupService {
    static let shared = iCloudBackupService()

    private let backupFileName = "SleepyBeanBackup.json"
    private let lastBackupKey = "sleepybean.lastBackupDate"

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    var localBackupFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(backupFileName, isDirectory: false)
    }

    var hasLocalBackup: Bool {
        FileManager.default.fileExists(atPath: localBackupFileURL.path)
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

    func saveBackup(context: ModelContext) throws {
        let data = try makeBackupData(context: context)
        try data.write(to: localBackupFileURL, options: .atomic)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    func restoreFromLocalBackup(context: ModelContext) throws {
        guard hasLocalBackup else { return }
        let data = try Data(contentsOf: localBackupFileURL)
        try restoreBackupData(data, context: context)
    }

    func backupIfPossible(context: ModelContext) async {
        guard AppPreferences.iCloudBackupEnabled else { return }
        do {
            try saveBackup(context: context)
        } catch {
            print("Backup failed: \(error.localizedDescription)")
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
            throw BackupError.invalidBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
