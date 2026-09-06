import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case invalidBackup
    case iCloudUnavailable
    case backupNotFound
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "The backup file could not be read."
        case .iCloudUnavailable:
            return "iCloud Drive is off. Sign in to iCloud and turn on iCloud Drive, then try again."
        case .backupNotFound:
            return "No SleepyBean backup was found in iCloud."
        case .emptyBackup:
            return "The backup file was empty (no sleep or feeding logs)."
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
        let backup = try SleepyBeanBackupEncoder.makeBackup(from: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    func restoreBackupData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: SleepyBeanBackupFile
        do {
            backup = try decoder.decode(SleepyBeanBackupFile.self, from: data)
        } catch {
            // Older backups may use the default Date encoding.
            let fallback = JSONDecoder()
            backup = try fallback.decode(SleepyBeanBackupFile.self, from: data)
        }
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
            try await saveToiCloud(context: context)
        } catch {
            print("Backup failed: \(error.localizedDescription)")
        }
    }

    func saveToiCloud(context: ModelContext) async throws {
        try context.save()
        let data = try makeBackupData(context: context)
        try data.write(to: localBackupFileURL, options: .atomic)

        guard let remoteURL = await iCloudBackupFileURL() else {
            throw BackupError.iCloudUnavailable
        }

        try await writeCoordinated(data: data, to: remoteURL)
        try await waitForUbiquitousUpload(remoteURL)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    func restoreFromiCloud(context: ModelContext) async throws {
        guard let remoteURL = await iCloudBackupFileURL() else {
            if hasLocalBackup {
                try restoreFromLocalBackup(context: context)
                return
            }
            throw BackupError.iCloudUnavailable
        }

        try await downloadIfNeeded(remoteURL)
        let data = try await readCoordinated(from: remoteURL)
        let summary = try decodeSummary(from: data)
        guard summary.babies > 0 else {
            throw BackupError.emptyBackup
        }

        try restoreBackupData(data, context: context)
        try data.write(to: localBackupFileURL, options: .atomic)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    func hasiCloudBackup() async -> Bool {
        if hasLocalBackup { return true }
        guard let remoteURL = await iCloudBackupFileURL() else { return false }
        if FileManager.default.fileExists(atPath: remoteURL.path) { return true }
        return FileManager.default.isUbiquitousItem(at: remoteURL)
    }

    func lastBackupSummary(context: ModelContext) throws -> String {
        let backup = try SleepyBeanBackupEncoder.makeBackup(from: context)
        let summary = SleepyBeanBackupEncoder.summary(of: backup)
        return "\(summary.sessions) sleep · \(summary.feeds) feeds"
    }

    private func decodeSummary(from data: Data) throws -> (babies: Int, sessions: Int, feeds: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let backup = try? decoder.decode(SleepyBeanBackupFile.self, from: data) {
            return SleepyBeanBackupEncoder.summary(of: backup)
        }
        let fallback = try JSONDecoder().decode(SleepyBeanBackupFile.self, from: data)
        return SleepyBeanBackupEncoder.summary(of: fallback)
    }

    private func iCloudBackupFileURL() async -> URL? {
        let containerID = CloudKitConfiguration.containerIdentifier
        let container = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        }.value

        guard let container else { return nil }

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appendingPathComponent(backupFileName, isDirectory: false)
    }

    private func writeCoordinated(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            var resumed = false
            coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinatorError) { fileURL in
                do {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try data.write(to: fileURL, options: .atomic)
                    } else {
                        FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: nil)
                        if !FileManager.default.fileExists(atPath: fileURL.path) {
                            try data.write(to: fileURL, options: .atomic)
                        }
                    }
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                } catch {
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }
            if let coordinatorError, !resumed {
                resumed = true
                continuation.resume(throwing: coordinatorError)
            }
        }
    }

    private func readCoordinated(from url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            var resumed = false
            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatorError) { fileURL in
                do {
                    let data = try Data(contentsOf: fileURL)
                    if !resumed {
                        resumed = true
                        continuation.resume(returning: data)
                    }
                } catch {
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }
            if let coordinatorError, !resumed {
                resumed = true
                continuation.resume(throwing: coordinatorError)
            }
        }
    }

    private func downloadIfNeeded(_ url: URL) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Query the ubiquity container so iOS discovers the remote file.
            _ = try? fm.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            if fm.isUbiquitousItem(at: url) || !fm.fileExists(atPath: url.path) {
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
        } else if fm.isUbiquitousItem(at: url) {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }

        for _ in 0..<50 {
            if fm.fileExists(atPath: url.path) {
                let values = try? url.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey,
                ])
                let status = values?.ubiquitousItemDownloadingStatus
                let downloading = values?.ubiquitousItemIsDownloading ?? false
                if status == .current || (!downloading && (status == nil || status == .current)) {
                    // Prefer a non-empty file.
                    if let attrs = try? fm.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? NSNumber,
                       size.intValue > 2 {
                        return
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        guard fm.fileExists(atPath: url.path) else {
            throw BackupError.backupNotFound
        }
    }

    private func waitForUbiquitousUpload(_ url: URL) async throws {
        let fm = FileManager.default
        guard fm.isUbiquitousItem(at: url) || fm.fileExists(atPath: url.path) else { return }

        for _ in 0..<40 {
            let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemIsUploadingKey,
                .ubiquitousItemUploadingErrorKey,
                .ubiquitousItemIsUploadedKey,
            ])
            if let error = values?.ubiquitousItemUploadingError {
                throw error
            }
            if values?.ubiquitousItemIsUploaded == true {
                return
            }
            if values?.ubiquitousItemIsUploading != true {
                // Not marked uploading anymore — treat as done for local-first containers.
                return
            }
            try await Task.sleep(for: .milliseconds(250))
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
