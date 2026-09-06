import CloudKit
import CoreData
import Foundation
import SwiftData

enum BabySharingError: LocalizedError {
    case cloudKitUnavailable
    case objectNotFound
    case shareUnavailable
    case coordinatorUnavailable

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

    var cachedSharedWithName: String? {
        let value = UserDefaults.standard.string(forKey: Self.sharedWithNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    func prepareShare(for baby: BabyProfile, modelContext: ModelContext) async throws -> CKShare {
        try modelContext.save()

        let share = try await preparePartnerZoneShare(for: baby)
        markShareActive()
        cacheParticipantNames(from: share)
        await pushPartnerData(for: baby)
        return share
    }

    func currentShare(for baby: BabyProfile) async -> CKShare? {
        let zoneID = CKRecordZone.ID(zoneName: Self.partnerZoneName, ownerName: CKCurrentUserDefaultName)
        let babyRecordID = CKRecord.ID(recordName: "baby-\(baby.id.uuidString)", zoneID: zoneID)
        if let share = try? await existingPartnerShare(for: babyRecordID) {
            cacheParticipantNames(from: share)
            return share
        }
        return nil
    }

    func sharedWithDisplayName(for baby: BabyProfile) async -> String? {
        if let share = await currentShare(for: baby) {
            let names = participantNames(from: share)
            if !names.isEmpty {
                let joined = names.joined(separator: ", ")
                UserDefaults.standard.set(joined, forKey: Self.sharedWithNameKey)
                return joined
            }
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
        let names = participantNames(from: share)
        if names.isEmpty {
            return
        }
        UserDefaults.standard.set(names.joined(separator: ", "), forKey: Self.sharedWithNameKey)
        markShareActive()
    }

    private func participantNames(from share: CKShare) -> [String] {
        let formatter = PersonNameComponentsFormatter()
        return share.participants.compactMap { participant -> String? in
            guard participant.role != .owner else { return nil }
            if let components = participant.userIdentity.nameComponents {
                let formatted = formatter.string(from: components)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !formatted.isEmpty { return formatted }
            }
            if let email = participant.userIdentity.lookupInfo?.emailAddress, !email.isEmpty {
                return email
            }
            if let phone = participant.userIdentity.lookupInfo?.phoneNumber, !phone.isEmpty {
                return phone
            }
            return nil
        }
    }

    private func clearShareState() {
        UserDefaults.standard.set(false, forKey: Self.hasShareKey)
        UserDefaults.standard.set(false, forKey: Self.isParticipantKey)
        UserDefaults.standard.removeObject(forKey: Self.sharedWithNameKey)
        UserDefaults.standard.removeObject(forKey: Self.zoneOwnerKey)
        UserDefaults.standard.removeObject(forKey: Self.zoneNameKey)
        UserDefaults.standard.removeObject(forKey: Self.babyUUIDKey)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        do {
            ensureConfigured()
            if let container = persistentContainer,
               let store = container.persistentStoreCoordinator.persistentStores.first {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    container.acceptShareInvitations(from: [metadata], into: store) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } else {
                _ = try await ckContainer.accept(metadata)
            }
        } catch {
            _ = try await ckContainer.accept(metadata)
        }

        rememberAcceptedShare(metadata)
        NotificationCenter.default.post(name: .sleepyBeanDidReceiveShare, object: nil)
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
        await pullPartnerData(into: modelContext)
    }

    func pushPartnerData(for baby: BabyProfile) async {
        guard hasPartnerShare, !isPushing else { return }
        isPushing = true
        defer { isPushing = false }

        do {
            let zoneID = partnerZoneID
            let database = partnerDatabase
            try await ensurePartnerZoneIfOwner()

            var records: [CKRecord] = []
            let babyRecord = partnerBabyRecord(for: baby, zoneID: zoneID)
            records.append(babyRecord)

            for session in baby.sleepSessions {
                records.append(partnerSessionRecord(for: session, baby: baby, babyRecord: babyRecord, zoneID: zoneID))
            }
            for feed in baby.feedEntries {
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
    }

    func pullPartnerData(into modelContext: ModelContext) async {
        guard hasPartnerShare else { return }

        do {
            let zoneID = partnerZoneID
            let database = partnerDatabase
            let records = try await fetchPartnerRecords(from: database, zoneID: zoneID)
            applyPartnerRecords(records, into: modelContext)
            try modelContext.save()
        } catch {
            print("Partner pull failed: \(error.localizedDescription)")
        }
    }

    private func preparePartnerZoneShare(for baby: BabyProfile) async throws -> CKShare {
        try await ensurePartnerZoneIfOwner()
        let zoneID = CKRecordZone.ID(zoneName: Self.partnerZoneName, ownerName: CKCurrentUserDefaultName)
        let babyRecord = partnerBabyRecord(for: baby, zoneID: zoneID)

        if let existingShare = try await existingPartnerShare(for: babyRecord.recordID) {
            return existingShare
        }

        let share = CKShare(rootRecord: babyRecord)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "\(baby.name) — SleepyBean" as CKRecordValue

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

    private func existingPartnerShare(for babyRecordID: CKRecord.ID) async throws -> CKShare? {
        do {
            let record = try await privateDatabase.record(for: babyRecordID)
            guard let shareRef = record.share else { return nil }
            return try await privateDatabase.record(for: shareRef.recordID) as? CKShare
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
            } else {
                baby = BabyProfile(name: name, birthDate: birthDate)
                baby.id = id
                modelContext.insert(baby)
            }

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

    private func partnerBabyRecord(for baby: BabyProfile, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "baby-\(baby.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: Self.babyRecordType, recordID: recordID)
        record["id"] = baby.id.uuidString as CKRecordValue
        record["name"] = baby.name as CKRecordValue
        record["birthDate"] = baby.birthDate as CKRecordValue
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
    }
}

extension Notification.Name {
    static let sleepyBeanDidReceiveShare = Notification.Name("sleepyBeanDidReceiveShare")
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
