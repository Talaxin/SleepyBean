import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case invalidBackup
    case iCloudUnavailable
    case backupNotFound
    case emptyBackup
    case refusedEmptyOverwrite

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "The backup file could not be read."
        case .iCloudUnavailable:
            return "iCloud Drive is off. Sign in to iCloud and turn on iCloud Drive, then try again."
        case .backupNotFound:
            return "No SleepyBean backup was found in iCloud."
        case .emptyBackup:
            return "The iCloud backup has no sleep or feeding logs."
        case .refusedEmptyOverwrite:
            return "Skipped backup — there are no logs to save, and a fuller backup is already in iCloud."
        }
    }
}

@MainActor
@Observable
final class iCloudBackupService {
    static let shared = iCloudBackupService()

    private let backupFileName = "SleepyBeanBackup.json"
    private let lastGoodFileName = "SleepyBeanBackup.lastGood.json"
    private let lastBackupKey = "sleepybean.lastBackupDate"
    private let lastGoodSummaryKey = "sleepybean.lastGoodBackupSummary"

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    var localBackupFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(backupFileName, isDirectory: false)
    }

    private var localLastGoodURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(lastGoodFileName, isDirectory: false)
    }

    var hasLocalBackup: Bool {
        FileManager.default.fileExists(atPath: localBackupFileURL.path)
            || FileManager.default.fileExists(atPath: localLastGoodURL.path)
    }

    func makeBackupData(context: ModelContext) throws -> Data {
        let backup = try SleepyBeanBackupEncoder.makeBackup(from: context)
        return try encode(backup)
    }

    @discardableResult
    func restoreBackupData(_ data: Data, context: ModelContext) throws -> UUID? {
        let backup = try decodeBackup(from: data)
        let summary = SleepyBeanBackupEncoder.summary(of: backup)
        guard summary.sessions > 0 || summary.feeds > 0 else {
            throw BackupError.emptyBackup
        }

        let babyID = try SleepyBeanBackupEncoder.restore(backup, into: context)
        NotificationCenter.default.post(
            name: .sleepyBeanDidRestoreBackup,
            object: nil,
            userInfo: babyID.map { ["babyID": $0] }
        )
        return babyID
    }

    func saveBackup(context: ModelContext) throws {
        let data = try makeBackupData(context: context)
        let summary = try decodeSummary(from: data)
        try data.write(to: localBackupFileURL, options: .atomic)
        if summary.sessions > 0 || summary.feeds > 0 {
            try data.write(to: localLastGoodURL, options: .atomic)
            UserDefaults.standard.set(
                "\(summary.sessions) sleep · \(summary.feeds) feeds",
                forKey: lastGoodSummaryKey
            )
        }
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    @discardableResult
    func restoreFromLocalBackup(context: ModelContext) throws -> UUID? {
        if let data = try? Data(contentsOf: localLastGoodURL),
           let summary = try? decodeSummary(from: data),
           summary.sessions > 0 || summary.feeds > 0 {
            return try restoreBackupData(data, context: context)
        }
        guard FileManager.default.fileExists(atPath: localBackupFileURL.path) else {
            throw BackupError.backupNotFound
        }
        let data = try Data(contentsOf: localBackupFileURL)
        return try restoreBackupData(data, context: context)
    }

    func backupIfPossible(context: ModelContext) async {
        guard AppPreferences.iCloudBackupEnabled else { return }
        do {
            let data = try makeBackupData(context: context)
            let summary = try decodeSummary(from: data)
            // Never auto-upload an empty wipe over a good backup.
            guard summary.sessions > 0 || summary.feeds > 0 else { return }
            try await saveToiCloud(context: context, allowEmpty: false)
        } catch BackupError.refusedEmptyOverwrite {
            return
        } catch {
            print("Backup failed: \(error.localizedDescription)")
        }
    }

    func saveToiCloud(context: ModelContext, allowEmpty: Bool = false) async throws {
        try context.save()
        let data = try makeBackupData(context: context)
        let summary = try decodeSummary(from: data)

        if summary.sessions == 0 && summary.feeds == 0 && !allowEmpty {
            if await remoteHasLogs() || localLastGoodHasLogs() {
                throw BackupError.refusedEmptyOverwrite
            }
        }

        try data.write(to: localBackupFileURL, options: .atomic)
        if summary.sessions > 0 || summary.feeds > 0 {
            try data.write(to: localLastGoodURL, options: .atomic)
            UserDefaults.standard.set(
                "\(summary.sessions) sleep · \(summary.feeds) feeds",
                forKey: lastGoodSummaryKey
            )
        }

        guard let remoteURL = await iCloudBackupFileURL(fileName: backupFileName) else {
            throw BackupError.iCloudUnavailable
        }

        // Protect a richer remote backup from an empty/local wipe.
        if summary.sessions == 0 && summary.feeds == 0 {
            if let remoteData = try? await readRemotePreferringGood(),
               let remoteSummary = try? decodeSummary(from: remoteData),
               remoteSummary.sessions + remoteSummary.feeds > 0 {
                throw BackupError.refusedEmptyOverwrite
            }
        }

        try await writeCoordinated(data: data, to: remoteURL)
        try await waitForUbiquitousUpload(remoteURL)

        if summary.sessions > 0 || summary.feeds > 0,
           let goodURL = await iCloudBackupFileURL(fileName: lastGoodFileName) {
            try await writeCoordinated(data: data, to: goodURL)
            try await waitForUbiquitousUpload(goodURL)
        }

        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }

    /// Returns summary string of the data that was actually encoded for the last successful save call.
    func summaryOfCurrentBackupData(context: ModelContext) throws -> String {
        let data = try makeBackupData(context: context)
        let summary = try decodeSummary(from: data)
        return "\(summary.sessions) sleep · \(summary.feeds) feeds"
    }

    func summaryOfStoredBackup() async -> String? {
        if let data = try? await readRemotePreferringGood(),
           let summary = try? decodeSummary(from: data) {
            return "\(summary.sessions) sleep · \(summary.feeds) feeds"
        }
        if let data = try? Data(contentsOf: localLastGoodURL),
           let summary = try? decodeSummary(from: data) {
            return "\(summary.sessions) sleep · \(summary.feeds) feeds"
        }
        if let data = try? Data(contentsOf: localBackupFileURL),
           let summary = try? decodeSummary(from: data) {
            return "\(summary.sessions) sleep · \(summary.feeds) feeds"
        }
        return UserDefaults.standard.string(forKey: lastGoodSummaryKey)
    }

    @discardableResult
    func restoreFromiCloud(context: ModelContext) async throws -> UUID? {
        let data = try await readRemotePreferringGood()
        let summary = try decodeSummary(from: data)
        guard summary.sessions > 0 || summary.feeds > 0 else {
            throw BackupError.emptyBackup
        }

        let babyID = try restoreBackupData(data, context: context)
        try data.write(to: localBackupFileURL, options: .atomic)
        try data.write(to: localLastGoodURL, options: .atomic)
        UserDefaults.standard.set(
            "\(summary.sessions) sleep · \(summary.feeds) feeds",
            forKey: lastGoodSummaryKey
        )
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
        return babyID
    }

    func hasiCloudBackup() async -> Bool {
        if localLastGoodHasLogs() || hasLocalBackup { return true }
        if let data = try? await readRemotePreferringGood(),
           let summary = try? decodeSummary(from: data),
           summary.sessions > 0 || summary.feeds > 0 {
            return true
        }
        return false
    }

    private func readRemotePreferringGood() async throws -> Data {
        // Prefer lastGood (never overwritten by empty wipe), then main file, then local.
        if let goodURL = await iCloudBackupFileURL(fileName: lastGoodFileName) {
            if FileManager.default.fileExists(atPath: goodURL.path)
                || FileManager.default.isUbiquitousItem(at: goodURL) {
                do {
                    try await downloadIfNeeded(goodURL)
                    let data = try await readCoordinated(from: goodURL)
                    let summary = try decodeSummary(from: data)
                    if summary.sessions > 0 || summary.feeds > 0 {
                        return data
                    }
                } catch {
                    // Fall through.
                }
            }
        }

        if let mainURL = await iCloudBackupFileURL(fileName: backupFileName) {
            if FileManager.default.fileExists(atPath: mainURL.path)
                || FileManager.default.isUbiquitousItem(at: mainURL) {
                try await downloadIfNeeded(mainURL)
                let data = try await readCoordinated(from: mainURL)
                let summary = try decodeSummary(from: data)
                if summary.sessions > 0 || summary.feeds > 0 {
                    return data
                }
            }
        }

        if let data = try? Data(contentsOf: localLastGoodURL) {
            let summary = try decodeSummary(from: data)
            if summary.sessions > 0 || summary.feeds > 0 {
                return data
            }
        }
        if let data = try? Data(contentsOf: localBackupFileURL) {
            let summary = try decodeSummary(from: data)
            if summary.sessions > 0 || summary.feeds > 0 {
                return data
            }
        }

        throw BackupError.emptyBackup
    }

    private func remoteHasLogs() async -> Bool {
        (try? await readRemotePreferringGood()) != nil
    }

    private func localLastGoodHasLogs() -> Bool {
        guard let data = try? Data(contentsOf: localLastGoodURL),
              let summary = try? decodeSummary(from: data) else {
            return false
        }
        return summary.sessions > 0 || summary.feeds > 0
    }

    private func encode(_ backup: SleepyBeanBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    private func decodeBackup(from data: Data) throws -> SleepyBeanBackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SleepyBeanBackupFile.self, from: data)
        } catch {
            return try JSONDecoder().decode(SleepyBeanBackupFile.self, from: data)
        }
    }

    private func decodeSummary(from data: Data) throws -> (babies: Int, sessions: Int, feeds: Int) {
        SleepyBeanBackupEncoder.summary(of: try decodeBackup(from: data))
    }

    private func iCloudBackupFileURL(fileName: String) async -> URL? {
        let containerID = CloudKitConfiguration.containerIdentifier
        let container = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        }.value

        guard let container else { return nil }

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appendingPathComponent(fileName, isDirectory: false)
    }

    private func writeCoordinated(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            var resumed = false
            coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinatorError) { fileURL in
                do {
                    try data.write(to: fileURL, options: .atomic)
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
