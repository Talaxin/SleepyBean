import Foundation
import SwiftData

struct SleepyBeanBackupFile: Codable {
    var version: Int
    var exportedAt: Date
    var babies: [BabyBackup]
}

struct BabyBackup: Codable {
    var id: UUID
    var name: String
    var birthDate: Date
    var createdAt: Date
    var sleepSessions: [SleepSessionBackup]
    var feedEntries: [FeedEntryBackup]
}

struct SleepSessionBackup: Codable {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var sleepType: String
    var notes: String
    var pausedAt: Date?
    var pauseAccumulated: TimeInterval?
}

struct FeedEntryBackup: Codable {
    var id: UUID
    var timestamp: Date
    var side: String
}

enum SleepyBeanBackupEncoder {
    static func makeBackup(from context: ModelContext) throws -> SleepyBeanBackupFile {
        let babies = try context.fetch(FetchDescriptor<BabyProfile>())
        let sessions = try context.fetch(FetchDescriptor<SleepSession>())
        let feeds = try context.fetch(FetchDescriptor<FeedEntry>())

        var sessionsByBaby: [UUID: [SleepSession]] = [:]
        var orphanSessions: [SleepSession] = []
        for session in sessions {
            if let babyID = session.baby?.id {
                sessionsByBaby[babyID, default: []].append(session)
            } else {
                orphanSessions.append(session)
            }
        }

        var feedsByBaby: [UUID: [FeedEntry]] = [:]
        var orphanFeeds: [FeedEntry] = []
        for feed in feeds {
            if let babyID = feed.baby?.id {
                feedsByBaby[babyID, default: []].append(feed)
            } else {
                orphanFeeds.append(feed)
            }
        }

        // Attach unlinked rows to the primary baby so they aren't dropped from backups.
        if let primaryID = babies.first?.id {
            if !orphanSessions.isEmpty {
                sessionsByBaby[primaryID, default: []].append(contentsOf: orphanSessions)
            }
            if !orphanFeeds.isEmpty {
                feedsByBaby[primaryID, default: []].append(contentsOf: orphanFeeds)
            }
        }

        return SleepyBeanBackupFile(
            version: 1,
            exportedAt: Date(),
            babies: babies.map { baby in
                let babySessions = sessionsByBaby[baby.id] ?? []
                let babyFeeds = feedsByBaby[baby.id] ?? []

                return BabyBackup(
                    id: baby.id,
                    name: baby.name,
                    birthDate: baby.birthDate,
                    createdAt: baby.createdAt,
                    sleepSessions: babySessions.map { session in
                        SleepSessionBackup(
                            id: session.id,
                            startTime: session.startTime,
                            endTime: session.endTime,
                            sleepType: session.sleepType,
                            notes: session.notes,
                            pausedAt: session.pausedAt,
                            pauseAccumulated: session.pauseAccumulated
                        )
                    },
                    feedEntries: babyFeeds.map { entry in
                        FeedEntryBackup(
                            id: entry.id,
                            timestamp: entry.timestamp,
                            side: entry.side
                        )
                    }
                )
            }
        )
    }

    /// Upsert restore — avoids CloudKit delete/recreate tombstone races that wipe newly restored rows.
    @discardableResult
    static func restore(_ backup: SleepyBeanBackupFile, into context: ModelContext) throws -> UUID? {
        let existingBabies = try context.fetch(FetchDescriptor<BabyProfile>())
        let existingSessions = try context.fetch(FetchDescriptor<SleepSession>())
        let existingFeeds = try context.fetch(FetchDescriptor<FeedEntry>())

        var babiesByID = Dictionary(uniqueKeysWithValues: existingBabies.map { ($0.id, $0) })
        var sessionsByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
        var feedsByID = Dictionary(uniqueKeysWithValues: existingFeeds.map { ($0.id, $0) })

        var restoredSessionIDs = Set<UUID>()
        var restoredFeedIDs = Set<UUID>()
        var restoredBabyIDs = Set<UUID>()
        var preferredBabyID: UUID?
        var preferredLogCount = -1

        for babyBackup in backup.babies {
            let baby: BabyProfile
            if let existing = babiesByID[babyBackup.id] {
                baby = existing
            } else if let existing = existingBabies.first(where: {
                $0.name.caseInsensitiveCompare(babyBackup.name) == .orderedSame
                    && Calendar.current.isDate($0.birthDate, inSameDayAs: babyBackup.birthDate)
            }) {
                baby = existing
                babiesByID[baby.id] = baby
            } else {
                baby = BabyProfile(name: babyBackup.name, birthDate: babyBackup.birthDate)
                baby.id = babyBackup.id
                context.insert(baby)
                babiesByID[baby.id] = baby
            }

            baby.name = babyBackup.name
            baby.birthDate = babyBackup.birthDate
            baby.createdAt = babyBackup.createdAt
            restoredBabyIDs.insert(baby.id)

            for sessionBackup in babyBackup.sleepSessions {
                let session: SleepSession
                if let existing = sessionsByID[sessionBackup.id] {
                    session = existing
                } else {
                    session = SleepSession(
                        startTime: sessionBackup.startTime,
                        endTime: sessionBackup.endTime,
                        sleepType: SleepType(rawValue: sessionBackup.sleepType) ?? .nap,
                        notes: sessionBackup.notes
                    )
                    session.id = sessionBackup.id
                    context.insert(session)
                    sessionsByID[session.id] = session
                }

                session.startTime = sessionBackup.startTime
                session.endTime = sessionBackup.endTime
                session.sleepType = sessionBackup.sleepType
                session.notes = sessionBackup.notes
                session.pausedAt = sessionBackup.pausedAt
                session.pauseAccumulated = sessionBackup.pauseAccumulated ?? 0
                session.baby = baby
                if !baby.sleepSessions.contains(where: { $0.id == session.id }) {
                    baby.sleepSessions.append(session)
                }
                restoredSessionIDs.insert(session.id)
            }

            for feedBackup in babyBackup.feedEntries {
                let entry: FeedEntry
                if let existing = feedsByID[feedBackup.id] {
                    entry = existing
                } else {
                    entry = FeedEntry(
                        timestamp: feedBackup.timestamp,
                        side: FeedSide(rawValue: feedBackup.side) ?? .left
                    )
                    entry.id = feedBackup.id
                    context.insert(entry)
                    feedsByID[entry.id] = entry
                }

                entry.timestamp = feedBackup.timestamp
                entry.side = feedBackup.side
                entry.baby = baby
                if !baby.feedEntries.contains(where: { $0.id == entry.id }) {
                    baby.feedEntries.append(entry)
                }
                restoredFeedIDs.insert(entry.id)
            }

            let logCount = babyBackup.sleepSessions.count + babyBackup.feedEntries.count
            if logCount > preferredLogCount {
                preferredLogCount = logCount
                preferredBabyID = baby.id
            }
        }

        let summary = SleepyBeanBackupEncoder.summary(of: backup)
        if summary.sessions > 0 || summary.feeds > 0 {
            for session in existingSessions where !restoredSessionIDs.contains(session.id) {
                context.delete(session)
            }
            for feed in existingFeeds where !restoredFeedIDs.contains(feed.id) {
                context.delete(feed)
            }
        }

        for baby in existingBabies where !restoredBabyIDs.contains(baby.id) {
            let stillNeeded = backup.babies.contains {
                $0.name.caseInsensitiveCompare(baby.name) == .orderedSame
                    && Calendar.current.isDate($0.birthDate, inSameDayAs: baby.birthDate)
            }
            if !stillNeeded {
                context.delete(baby)
            }
        }

        try context.save()
        return preferredBabyID ?? restoredBabyIDs.first
    }

    static func summary(of backup: SleepyBeanBackupFile) -> (babies: Int, sessions: Int, feeds: Int) {
        let sessions = backup.babies.reduce(0) { $0 + $1.sleepSessions.count }
        let feeds = backup.babies.reduce(0) { $0 + $1.feedEntries.count }
        return (backup.babies.count, sessions, feeds)
    }
}

extension Notification.Name {
    static let sleepyBeanDidRestoreBackup = Notification.Name("sleepyBeanDidRestoreBackup")
}
