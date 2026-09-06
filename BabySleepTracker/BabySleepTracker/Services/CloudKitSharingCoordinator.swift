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

    private var persistentContainer: NSPersistentCloudKitContainer?
    private var storeURL: URL?

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

    func prepareShare(for baby: BabyProfile, modelContext: ModelContext) async throws -> CKShare {
        guard SleepyBeanModelContainer.isCloudKitEnabled else {
            throw BabySharingError.cloudKitUnavailable
        }
        ensureConfigured()
        guard let container = persistentContainer else {
            throw BabySharingError.coordinatorUnavailable
        }
        guard let managedObject = managedObject(for: baby, modelContext: modelContext) else {
            throw BabySharingError.objectNotFound
        }

        if let existingShare = try existingShare(for: baby, modelContext: modelContext) {
            existingShare[CKShare.SystemFieldKey.title] = "\(baby.name) — SleepyBean" as CKRecordValue
            return existingShare
        }

        let babyName = baby.name
        return try await withCheckedThrowingContinuation { continuation in
            container.share([managedObject], to: nil) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let share else {
                    continuation.resume(throwing: BabySharingError.shareUnavailable)
                    return
                }

                share[CKShare.SystemFieldKey.title] = "\(babyName) — SleepyBean" as CKRecordValue
                continuation.resume(returning: share)
            }
        }
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        ensureConfigured()
        guard let container = persistentContainer else {
            throw BabySharingError.coordinatorUnavailable
        }

        guard let store = container.persistentStoreCoordinator.persistentStores.first else {
            throw BabySharingError.coordinatorUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
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
