import CloudKit
import CoreData
import Foundation
import SwiftData
import UIKit

enum BabySharingError: LocalizedError {
    case cloudKitUnavailable
    case objectNotFound
    case shareUnavailable
    case coordinatorUnavailable
    case invalidInviteCode

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            return "iCloud sharing requires signing in to iCloud and building with your developer account."
        case .objectNotFound:
            return "Could not find this baby profile in storage."
        case .shareUnavailable:
            return "Could not create or load the share."
        case .coordinatorUnavailable:
            return "CloudKit sharing is not ready yet. Try again in a moment."
        case .invalidInviteCode:
            return "That invite code wasn’t found. Ask them to create a new invite in Settings."
        }
    }
}

@MainActor
final class CloudKitSharingCoordinator {
    static let shared = CloudKitSharingCoordinator()

    static let hasShareKey = "partner.hasShare"
    static let isParticipantKey = "partner.isParticipant"
    static let zoneOwnerKey = "partner.zoneOwner"
    static let zoneNameKey = "partner.zoneName"
    static let babyUUIDKey = "partner.babyUUID"
    static let partnerZoneName = "SleepyBeanPartner"
    static let babyRecordType = "PartnerBaby"
    static let sessionRecordType = "PartnerSession"
    static let feedRecordType = "PartnerFeed"

    private var persistentContainer: NSPersistentCloudKitContainer?
    private var storeURL: URL?
    private var isPushing = false

    private init() {}

    var isReady: Bool {
        persistentContainer != nil && SleepyBeanModelContainer.isCloudKitEnabled
    }

    var ckContainer: CKContainer {
        CKContainer(identifier: CloudKitConfiguration.containerIdentifier)
    }

    func configure(storeURL: URL) {
        guard SleepyBeanModelContainer.isCloudKitEnabled else { return }
        guard self.storeURL != storeURL || persistentContainer == nil else { return }

        self.storeURL = storeURL

        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
            for: [BabyProfile.self, SleepSession.self, FeedEntry.self]
        ) else {
            print("Could not build managed object model for sharing.")
            return
        }

        let container = NSPersistentCloudKitContainer(
            name: "SleepyBean",
            managedObjectModel: managedObjectModel
        )

        let description = NSPersistentStoreDescription(url: storeURL)
        let cloudKitOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: CloudKitConfiguration.containerIdentifier
        )
        description.cloudKitContainerOptions = cloudKitOptions
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldAddStoreAsynchronously = false

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                print("CloudKit sharing store load failed: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        persistentContainer = container
    }

    func existingShare(for baby: BabyProfile, modelContext: ModelContext) throws -> CKShare? {
        ensureConfigured()
        guard let container = persistentContainer else { return nil }
        guard let managedObject = managedObject(for: baby, modelContext: modelContext) else {
            throw BabySharingError.objectNotFound
        }

        let shares = try container.fetchShares(matching: [managedObject.objectID])
        return shares[managedObject.objectID]
    }

    var hasPartnerShare: Bool {
        UserDefaults.standard.bool(forKey: Self.hasShareKey)
    }

    static let sharedWithNameKey = "partner.sharedWithName"
    static let customNameKey = "partner.customName"
    static let inviteHintKey = "partner.inviteHint"
    static let myNameKey = "partner.myName"
    static let inviteAcceptedKey = "partner.inviteAccepted"
    static let inviteCodeKey = "partner.inviteCode"
    static let inviteRecordPrefix = "invite-"

    var cachedSharedWithName: String? {
        let custom = UserDefaults.standard.string(forKey: Self.customNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        let value = UserDefaults.standard.string(forKey: Self.sharedWithNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty, !Self.isContactHandle(value) { return value }
        let hint = UserDefaults.standard.string(forKey: Self.inviteHintKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (hint?.isEmpty == false) ? hint : ((value?.isEmpty == false) ? value : nil)
    }

    var hasCustomPartnerName: Bool {
        let custom = UserDefaults.standard.string(forKey: Self.customNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom?.isEmpty == false
    }

    func setCustomPartnerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.customNameKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.customNameKey)
            UserDefaults.standard.set(trimmed, forKey: Self.sharedWithNameKey)
        }
        NotificationCenter.default.post(name: .sleepyBeanPartnerDataDidChange, object: nil)
    }

    func prepareShare(for baby: BabyProfile, modelContext: ModelContext) async throws -> CKShare {
        try modelContext.save()

        let share = try await preparePartnerZoneShare(for: baby)
        markShareActive()
        cacheParticipantNames(from: share)
        _ = try? await publishInvite(for: share)
        await subscribeToPartnerChanges()
        await pushPartnerData(for: baby, modelContext: modelContext)
        return share
    }

    func currentShare(for baby: BabyProfile) async -> CKShare? {
        let zoneID = partnerZoneID
        let babyUUID = UserDefaults.standard.string(forKey: Self.babyUUIDKey) ?? baby.id.uuidString
        let babyRecordID = CKRecord.ID(recordName: "baby-\(babyUUID)", zoneID: zoneID)
        if let share = try? await existingPartnerShare(for: babyRecordID) {
            cacheParticipantNames(from: share)
            return share
        }
        return nil
    }

    func sharedWithDisplayName(for baby: BabyProfile) async -> String? {
        await hydrateShareStateFromCloud()
        if let share = await currentShare(for: baby) {
            cacheParticipantNames(from: share)
        }
        return cachedSharedWithName
    }

    func stopSharing(for baby: BabyProfile) async throws {
        let isParticipant = UserDefaults.standard.bool(forKey: Self.isParticipantKey)

        if isParticipant {
            // Leave the shared zone by deleting the share from the shared database when possible.
            let zoneID = partnerZoneID
            let babyRecordID = CKRecord.ID(recordName: "baby-\(baby.id.uuidString)", zoneID: zoneID)
            if let record = try? await partnerDatabase.record(for: babyRecordID),
               let shareRef = record.share {
                _ = try await partnerDatabase.modifyRecords(
                    saving: [],
                    deleting: [shareRef.recordID],
                    savePolicy: .allKeys,
                    atomically: false
                )
            }
        } else if let share = await currentShare(for: baby) {
            _ = try await privateDatabase.modifyRecords(
                saving: [],
                deleting: [share.recordID],
                savePolicy: .allKeys,
                atomically: false
            )
        }

        clearShareState()
    }

    func cacheParticipantNames(from share: CKShare) {
        let isParticipant = UserDefaults.standard.bool(forKey: Self.isParticipantKey)
        let people = isParticipant ? [share.owner] : share.participants.filter { $0.role != .owner }
        var realNames: [String] = []
        var handles: [String] = []
        for person in people {
            let parsed = identityParts(person.userIdentity)
            if let name = parsed.name { realNames.append(name) }
            if let handle = parsed.handle { handles.append(handle) }
        }
        if !handles.isEmpty {
            UserDefaults.standard.set(handles.joined(separator: ", "), forKey: Self.inviteHintKey)
        }
        if !realNames.isEmpty, !hasCustomPartnerName {
            UserDefaults.standard.set(realNames.joined(separator: ", "), forKey: Self.sharedWithNameKey)
        }
        let accepted = share.participants.contains {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }
        UserDefaults.standard.set(accepted, forKey: Self.inviteAcceptedKey)
        markShareActive()
    }

    private func identityParts(_ identity: CKUserIdentity) -> (name: String?, handle: String?) {
        let formatter = PersonNameComponentsFormatter()
        var name: String?
        if let components = identity.nameComponents {
            let formatted = formatter.string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty, !Self.isContactHandle(formatted) {
                name = formatted
            }
        }
        let email = identity.lookupInfo?.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = identity.lookupInfo?.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = [phone, email].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first
        return (name, handle)
    }

    static func isContactHandle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return true }
        let letters = trimmed.filter(\.isLetter)
        let digits = trimmed.filter(\.isNumber)
        return letters.isEmpty && digits.count >= 7
    }

    private func clearShareState() {
        UserDefaults.standard.set(false, forKey: Self.hasShareKey)
        UserDefaults.standard.set(false, forKey: Self.isParticipantKey)
        UserDefaults.standard.removeObject(forKey: Self.sharedWithNameKey)
        UserDefaults.standard.removeObject(forKey: Self.customNameKey)
        UserDefaults.standard.removeObject(forKey: Self.inviteHintKey)
        UserDefaults.standard.removeObject(forKey: Self.inviteAcceptedKey)
        UserDefaults.standard.removeObject(forKey: Self.inviteCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.zoneOwnerKey)
        UserDefaults.standard.removeObject(forKey: Self.zoneNameKey)
        UserDefaults.standard.removeObject(forKey: Self.babyUUIDKey)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        _ = try await container.accept(metadata)
        rememberAcceptedShare(metadata)
        await subscribeToPartnerChanges()
        NotificationCenter.default.post(name: .sleepyBeanDidReceiveShare, object: nil)
        NotificationCenter.default.post(name: .sleepyBeanPartnerDataDidChange, object: nil)
    }

    func acceptShare(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let metadata = try await fetchShareMetadata(from: url)
            try await acceptShare(metadata: metadata)
        } catch {
            print("Accept share URL failed: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .sleepyBeanShareAcceptFailed,
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }

    func acceptShareFromPasteboard() async {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: pasted), Self.isShareURL(url) {
            await acceptShare(from: url)
            return
        }
        let code = pasted.uppercased().filter(\.isLetter).isEmpty && pasted.count >= 4
            ? pasted.uppercased()
            : pasted
        if code.count >= 4 {
            do {
                try await join(usingCode: code)
                return
            } catch {
                NotificationCenter.default.post(
                    name: .sleepyBeanShareAcceptFailed,
                    object: nil,
                    userInfo: ["error": error.localizedDescription]
                )
                return
            }
        }
        NotificationCenter.default.post(
            name: .sleepyBeanShareAcceptFailed,
            object: nil,
            userInfo: ["error": "Copy the invite code or iCloud link, then tap Join."]
        )
    }

    func join(usingCode rawCode: String) async throws {
        let code = Self.normalizedInviteCode(rawCode)
        guard code.count == 6 else {
            throw BabySharingError.invalidInviteCode
        }
        let recordID = CKRecord.ID(recordName: Self.inviteRecordPrefix + code)
        do {
            let record = try await ckContainer.publicCloudDatabase.record(for: recordID)
            guard let urlString = record["url"] as? String, let url = URL(string: urlString) else {
                throw BabySharingError.invalidInviteCode
            }
            let metadata = try await fetchShareMetadata(from: url)
            try await acceptShare(metadata: metadata)
        } catch let error as BabySharingError {
            throw error
        } catch {
            throw BabySharingError.invalidInviteCode
        }
    }

    var cachedInviteCode: String? {
        let value = UserDefaults.standard.string(forKey: Self.inviteCodeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    func publishInvite(for share: CKShare) async throws -> String {
        guard let url = share.url else { throw BabySharingError.shareUnavailable }
        if let existing = cachedInviteCode {
            return existing
        }
        let code = Self.makeInviteCode()
        let record = CKRecord(
            recordType: "PartnerInvite",
            recordID: CKRecord.ID(recordName: Self.inviteRecordPrefix + code)
        )
        record["code"] = code as CKRecordValue
        record["url"] = url.absoluteString as CKRecordValue
        _ = try await ckContainer.publicCloudDatabase.save(record)
        UserDefaults.standard.set(code, forKey: Self.inviteCodeKey)
        return code
    }

    static func normalizedInviteCode(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func makeInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    func inviteURL(for baby: BabyProfile) async -> URL? {
        await currentShare(for: baby)?.url
    }

    static func isShareURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        if url.isFileURL { return true }
        if url.pathExtension.lowercased() == "ckshare" { return true }
        return value.contains("icloud.com") && value.contains("share")
    }

    private func fetchShareMetadata(from url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = true
            var didFinish = false
            operation.perShareMetadataResultBlock = { _, result in
                guard !didFinish else { return }
                didFinish = true
                continuation.resume(with: result)
            }
            operation.fetchShareMetadataResultBlock = { result in
                if case .failure(let error) = result, !didFinish {
                    didFinish = true
                    continuation.resume(throwing: error)
                }
            }
            ckContainer.add(operation)
        }
    }

    func isShared(_ baby: BabyProfile, modelContext: ModelContext) -> Bool {
        (try? existingShare(for: baby, modelContext: modelContext)) != nil
    }

    private func ensureConfigured() {
        if let storeURL = SleepyBeanModelContainer.storeURL {
            configure(storeURL: storeURL)
        }
    }

    private func managedObject(for baby: BabyProfile, modelContext: ModelContext) -> NSManagedObject? {
        if let coreDataContext = modelContext.coreDataContext {
            if let objectID = baby.persistentModelID.managedObjectID(in: coreDataContext),
               let object = try? coreDataContext.existingObject(with: objectID) {
                return object
            }

            let request = NSFetchRequest<NSManagedObject>(entityName: "BabyProfile")
            request.predicate = NSPredicate(format: "id == %@", baby.id as CVarArg)
            request.fetchLimit = 1
            if let object = try? coreDataContext.fetch(request).first {
                return object
            }
        }

        guard let container = persistentContainer else { return nil }
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "BabyProfile")
        request.predicate = NSPredicate(format: "id == %@", baby.id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func consumePendingShare(modelContext: ModelContext) async {
        await hydrateShareStateFromCloud()
        await pullPartnerData(into: modelContext)
        await subscribeToPartnerChanges()
    }

    func handleRemotePartnerNotification() {
        NotificationCenter.default.post(name: .sleepyBeanDidReceiveShare, object: nil)
    }

    func pushPartnerData(for baby: BabyProfile, modelContext: ModelContext? = nil) async {
        guard hasPartnerShare else { return }
        if isPushing {
            needsAnotherPush = true
            return
        }
        isPushing = true
        defer { isPushing = false }

        do {
            let zoneID = partnerZoneID
            let database = partnerDatabase
            try await ensurePartnerZoneIfOwner()

            let sessions = sessionsToPush(for: baby, modelContext: modelContext)
            let feeds = feedsToPush(for: baby, modelContext: modelContext)

            var records: [CKRecord] = []
            let babyRecord = await partnerBabyRecord(for: baby, zoneID: zoneID)
            records.append(babyRecord)

            for session in sessions {
                records.append(partnerSessionRecord(for: session, baby: baby, babyRecord: babyRecord, zoneID: zoneID))
            }
            for feed in feeds {
                records.append(partnerFeedRecord(for: feed, baby: baby, babyRecord: babyRecord, zoneID: zoneID))
            }

            _ = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            UserDefaults.standard.set(baby.id.uuidString, forKey: Self.babyUUIDKey)
        } catch {
            print("Partner push failed: \(error.localizedDescription)")
        }

        if needsAnotherPush {
            needsAnotherPush = false
            await pushPartnerData(for: baby, modelContext: modelContext)
        }
    }

    func pullPartnerData(into modelContext: ModelContext) async {
        guard hasPartnerShare else { return }

        do {
            let zoneID = partnerZoneID
            let database = partnerDatabase
            let records = try await fetchPartnerRecords(from: database, zoneID: zoneID)
            applyPartnerRecords(records, into: modelContext)
            try modelContext.save()
            NotificationCenter.default.post(name: .sleepyBeanPartnerDataDidChange, object: nil)
        } catch {
            print("Partner pull failed: \(error.localizedDescription)")
        }
    }

    private var needsAnotherPush = false

    private func sessionsToPush(for baby: BabyProfile, modelContext: ModelContext?) -> [SleepSession] {
        guard let modelContext else { return baby.sleepSessions }
        let fetched = (try? modelContext.fetch(FetchDescriptor<SleepSession>())) ?? []
        let linked = fetched.filter { $0.baby?.id == baby.id }
        return linked.isEmpty ? baby.sleepSessions : linked
    }

    private func feedsToPush(for baby: BabyProfile, modelContext: ModelContext?) -> [FeedEntry] {
        guard let modelContext else { return baby.feedEntries }
        let fetched = (try? modelContext.fetch(FetchDescriptor<FeedEntry>())) ?? []
        let linked = fetched.filter { $0.baby?.id == baby.id }
        return linked.isEmpty ? baby.feedEntries : linked
    }

    private func preparePartnerZoneShare(for baby: BabyProfile) async throws -> CKShare {
        try await ensurePartnerZoneIfOwner()
        let zoneID = CKRecordZone.ID(zoneName: Self.partnerZoneName, ownerName: CKCurrentUserDefaultName)
        let babyRecord = await partnerBabyRecord(for: baby, zoneID: zoneID)

        if let existingShare = try await existingPartnerShare(for: babyRecord.recordID) {
            if existingShare.publicPermission != .readWrite {
                existingShare.publicPermission = .readWrite
                _ = try? await privateDatabase.save(existingShare)
            }
            return existingShare
        }

        let share = CKShare(rootRecord: babyRecord)
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = "\(baby.name) on SleepyBean" as CKRecordValue
        if let thumb = shareThumbnailData() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
        }

        let results = try await privateDatabase.modifyRecords(
            saving: [babyRecord, share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )

        UserDefaults.standard.set(false, forKey: Self.isParticipantKey)
        UserDefaults.standard.set(CKCurrentUserDefaultName, forKey: Self.zoneOwnerKey)
        UserDefaults.standard.set(Self.partnerZoneName, forKey: Self.zoneNameKey)
        UserDefaults.standard.set(baby.id.uuidString, forKey: Self.babyUUIDKey)

        for (_, result) in results.saveResults {
            if case .success(let record) = result, let savedShare = record as? CKShare {
                return savedShare
            }
        }

        throw BabySharingError.shareUnavailable
    }

    private func shareThumbnailData() -> Data? {
        let url = Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png")
            ?? Bundle.main.url(
                forResource: "AppIcon-1024",
                withExtension: "png",
                subdirectory: "AppIcon.appiconset"
            )
        if let url, let data = try? Data(contentsOf: url) {
            return data
        }
        return UIImage(named: "AppIcon")?.pngData()
    }

    private func existingPartnerShare(for babyRecordID: CKRecord.ID) async throws -> CKShare? {
        do {
            let record = try await partnerDatabase.record(for: babyRecordID)
            guard let shareRef = record.share else { return nil }
            return try await partnerDatabase.record(for: shareRef.recordID) as? CKShare
        } catch {
            return nil
        }
    }

    private func ensurePartnerZoneIfOwner() async throws {
        guard !UserDefaults.standard.bool(forKey: Self.isParticipantKey) else { return }
        let zone = CKRecordZone(zoneName: Self.partnerZoneName)
        do {
            _ = try await privateDatabase.save(zone)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("already") || message.contains("exists") {
                return
            }
            throw error
        }
    }

    private func fetchPartnerRecords(from database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        for type in [Self.babyRecordType, Self.sessionRecordType, Self.feedRecordType] {
            let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
            for (_, result) in matchResults {
                if let record = try? result.get() {
                    records.append(record)
                }
            }
        }
        return records
    }

    private func applyPartnerRecords(_ records: [CKRecord], into modelContext: ModelContext) {
        let babies = (try? modelContext.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let babyRecords = records.filter { $0.recordType == Self.babyRecordType }

        for record in babyRecords {
            guard let idString = record["id"] as? String, let id = UUID(uuidString: idString) else { continue }
            let name = record["name"] as? String ?? "Baby"
            let birthDate = record["birthDate"] as? Date ?? Date()

            let baby: BabyProfile
            if let existing = babies.first(where: { $0.id == id }) {
                baby = existing
                baby.name = name
                baby.birthDate = birthDate
            } else if let existing = babies.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
                    && Calendar.current.isDate($0.birthDate, inSameDayAs: birthDate)
            }) {
                baby = existing
                baby.id = id
                baby.name = name
                baby.birthDate = birthDate
            } else {
                baby = BabyProfile(name: name, birthDate: birthDate)
                baby.id = id
                modelContext.insert(baby)
            }

            if let ownerName = record["ownerName"] as? String,
               !ownerName.isEmpty,
               UserDefaults.standard.bool(forKey: Self.isParticipantKey),
               !hasCustomPartnerName,
               !Self.isContactHandle(ownerName) {
                UserDefaults.standard.set(ownerName, forKey: Self.sharedWithNameKey)
            }

            UserDefaults.standard.set(id.uuidString, forKey: Self.babyUUIDKey)

            let sessions = baby.sleepSessions
            for sessionRecord in records where sessionRecord.recordType == Self.sessionRecordType {
                guard let sessionIDString = sessionRecord["id"] as? String,
                      let sessionID = UUID(uuidString: sessionIDString),
                      let babyIDString = sessionRecord["babyId"] as? String,
                      babyIDString == id.uuidString
                else { continue }

                let start = sessionRecord["startTime"] as? Date ?? Date()
                let end = sessionRecord["endTime"] as? Date
                let type = SleepType(rawValue: sessionRecord["sleepType"] as? String ?? "") ?? .nap
                let notes = sessionRecord["notes"] as? String ?? ""
                let pausedAt = sessionRecord["pausedAt"] as? Date
                let pauseAccumulated = sessionRecord["pauseAccumulated"] as? Double ?? 0

                if let existing = sessions.first(where: { $0.id == sessionID }) {
                    existing.startTime = start
                    existing.endTime = end
                    existing.sleepType = type.rawValue
                    existing.notes = notes
                    existing.pausedAt = pausedAt
                    existing.pauseAccumulated = pauseAccumulated
                } else {
                    let session = SleepSession(startTime: start, endTime: end, sleepType: type, notes: notes)
                    session.id = sessionID
                    session.pausedAt = pausedAt
                    session.pauseAccumulated = pauseAccumulated
                    session.baby = baby
                    modelContext.insert(session)
                }
            }

            let feeds = baby.feedEntries
            for feedRecord in records where feedRecord.recordType == Self.feedRecordType {
                guard let feedIDString = feedRecord["id"] as? String,
                      let feedID = UUID(uuidString: feedIDString),
                      let babyIDString = feedRecord["babyId"] as? String,
                      babyIDString == id.uuidString
                else { continue }

                let timestamp = feedRecord["timestamp"] as? Date ?? Date()
                let side = FeedSide(rawValue: feedRecord["side"] as? String ?? "") ?? .left

                if let existing = feeds.first(where: { $0.id == feedID }) {
                    existing.timestamp = timestamp
                    existing.side = side.rawValue
                } else {
                    let feed = FeedEntry(timestamp: timestamp, side: side)
                    feed.id = feedID
                    feed.baby = baby
                    modelContext.insert(feed)
                }
            }
        }
    }

    private func partnerBabyRecord(for baby: BabyProfile, zoneID: CKRecordZone.ID) async -> CKRecord {
        let recordID = CKRecord.ID(recordName: "baby-\(baby.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: Self.babyRecordType, recordID: recordID)
        record["id"] = baby.id.uuidString as CKRecordValue
        record["name"] = baby.name as CKRecordValue
        record["birthDate"] = baby.birthDate as CKRecordValue
        if let ownerName = await currentUserDisplayName() {
            record["ownerName"] = ownerName as CKRecordValue
        }
        return record
    }

    private func partnerSessionRecord(
        for session: SleepSession,
        baby: BabyProfile,
        babyRecord: CKRecord,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "session-\(session.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: Self.sessionRecordType, recordID: recordID)
        record["id"] = session.id.uuidString as CKRecordValue
        record["babyId"] = baby.id.uuidString as CKRecordValue
        record["startTime"] = session.startTime as CKRecordValue
        if let endTime = session.endTime {
            record["endTime"] = endTime as CKRecordValue
        }
        record["sleepType"] = session.sleepType as CKRecordValue
        record["notes"] = session.notes as CKRecordValue
        if let pausedAt = session.pausedAt {
            record["pausedAt"] = pausedAt as CKRecordValue
        }
        record["pauseAccumulated"] = session.pauseAccumulated as CKRecordValue
        record.setParent(babyRecord)
        return record
    }

    private func partnerFeedRecord(
        for feed: FeedEntry,
        baby: BabyProfile,
        babyRecord: CKRecord,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "feed-\(feed.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: Self.feedRecordType, recordID: recordID)
        record["id"] = feed.id.uuidString as CKRecordValue
        record["babyId"] = baby.id.uuidString as CKRecordValue
        record["timestamp"] = feed.timestamp as CKRecordValue
        record["side"] = feed.side as CKRecordValue
        record.setParent(babyRecord)
        return record
    }

    private var privateDatabase: CKDatabase {
        ckContainer.privateCloudDatabase
    }

    private var partnerDatabase: CKDatabase {
        UserDefaults.standard.bool(forKey: Self.isParticipantKey)
            ? ckContainer.sharedCloudDatabase
            : ckContainer.privateCloudDatabase
    }

    private var partnerZoneID: CKRecordZone.ID {
        let zoneName = UserDefaults.standard.string(forKey: Self.zoneNameKey) ?? Self.partnerZoneName
        let owner = UserDefaults.standard.string(forKey: Self.zoneOwnerKey) ?? CKCurrentUserDefaultName
        return CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
    }

    private func markShareActive() {
        UserDefaults.standard.set(true, forKey: Self.hasShareKey)
    }

    private func rememberAcceptedShare(_ metadata: CKShare.Metadata) {
        markShareActive()
        UserDefaults.standard.set(true, forKey: Self.isParticipantKey)
        UserDefaults.standard.set(metadata.share.recordID.zoneID.ownerName, forKey: Self.zoneOwnerKey)
        UserDefaults.standard.set(metadata.share.recordID.zoneID.zoneName, forKey: Self.zoneNameKey)
        UserDefaults.standard.set(true, forKey: Self.inviteAcceptedKey)
        cacheParticipantNames(from: metadata.share)
        let ownerParts = identityParts(metadata.ownerIdentity)
        if let name = ownerParts.name, !hasCustomPartnerName {
            UserDefaults.standard.set(name, forKey: Self.sharedWithNameKey)
        }
        if let handle = ownerParts.handle {
            UserDefaults.standard.set(handle, forKey: Self.inviteHintKey)
        }
    }

    func hydrateShareStateFromCloud() async {
        if let sharedZones = try? await ckContainer.sharedCloudDatabase.allRecordZones(),
           let zone = sharedZones.first(where: { $0.zoneID.zoneName == Self.partnerZoneName }) {
            UserDefaults.standard.set(true, forKey: Self.hasShareKey)
            UserDefaults.standard.set(true, forKey: Self.isParticipantKey)
            UserDefaults.standard.set(zone.zoneID.ownerName, forKey: Self.zoneOwnerKey)
            UserDefaults.standard.set(zone.zoneID.zoneName, forKey: Self.zoneNameKey)
            await cacheNamesFromPartnerZone(database: ckContainer.sharedCloudDatabase, zoneID: zone.zoneID)
            return
        }

        let privateZoneID = CKRecordZone.ID(zoneName: Self.partnerZoneName, ownerName: CKCurrentUserDefaultName)
        guard let records = try? await fetchPartnerRecords(from: privateDatabase, zoneID: privateZoneID) else { return }
        for record in records where record.recordType == Self.babyRecordType && record.share != nil {
            UserDefaults.standard.set(true, forKey: Self.hasShareKey)
            UserDefaults.standard.set(false, forKey: Self.isParticipantKey)
            UserDefaults.standard.set(CKCurrentUserDefaultName, forKey: Self.zoneOwnerKey)
            UserDefaults.standard.set(Self.partnerZoneName, forKey: Self.zoneNameKey)
            if let id = record["id"] as? String {
                UserDefaults.standard.set(id, forKey: Self.babyUUIDKey)
            }
            if let share = try? await existingPartnerShare(for: record.recordID) {
                cacheParticipantNames(from: share)
            }
            return
        }
    }

    private func cacheNamesFromPartnerZone(database: CKDatabase, zoneID: CKRecordZone.ID) async {
        guard let records = try? await fetchPartnerRecords(from: database, zoneID: zoneID) else { return }
        if let baby = records.first(where: { $0.recordType == Self.babyRecordType }) {
            if let id = baby["id"] as? String {
                UserDefaults.standard.set(id, forKey: Self.babyUUIDKey)
            }
            if let ownerName = baby["ownerName"] as? String,
               !ownerName.isEmpty,
               !hasCustomPartnerName,
               !Self.isContactHandle(ownerName) {
                UserDefaults.standard.set(ownerName, forKey: Self.sharedWithNameKey)
            }
            if let share = try? await existingPartnerShare(for: baby.recordID) {
                cacheParticipantNames(from: share)
            }
        }
    }

    func subscribeToPartnerChanges() async {
        guard hasPartnerShare else { return }
        let suffix = UserDefaults.standard.bool(forKey: Self.isParticipantKey) ? "shared" : "private"
        let subscription = CKDatabaseSubscription(subscriptionID: "sleepybean-partner-\(suffix)")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await partnerDatabase.save(subscription)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("duplicate") || message.contains("already") {
                return
            }
            print("Partner subscription failed: \(error.localizedDescription)")
        }
    }

    private func currentUserDisplayName() async -> String? {
        if let cached = UserDefaults.standard.string(forKey: Self.myNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty,
           !Self.isContactHandle(cached) {
            return cached
        }
        return nil
    }
}

extension Notification.Name {
    static let sleepyBeanDidReceiveShare = Notification.Name("sleepyBeanDidReceiveShare")
    static let sleepyBeanPartnerDataDidChange = Notification.Name("sleepyBeanPartnerDataDidChange")
    static let sleepyBeanShareAcceptFailed = Notification.Name("sleepyBeanShareAcceptFailed")
}

private extension ModelContext {
    var coreDataContext: NSManagedObjectContext? {
        var mirror: Mirror? = Mirror(reflecting: self)
        while let currentMirror = mirror {
            for child in currentMirror.children {
                if let context = child.value as? NSManagedObjectContext {
                    return context
                }
            }
            mirror = currentMirror.superclassMirror
        }
        return nil
    }
}

private extension PersistentIdentifier {
    func managedObjectID(in context: NSManagedObjectContext) -> NSManagedObjectID? {
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        guard
            let data = try? JSONEncoder().encode(self),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let implementation = json["implementation"] as? [String: Any],
            let uriString = implementation["uriRepresentation"] as? String,
            let uri = URL(string: uriString)
        else {
            return nil
        }
        return coordinator.managedObjectID(forURIRepresentation: uri)
    }
}
