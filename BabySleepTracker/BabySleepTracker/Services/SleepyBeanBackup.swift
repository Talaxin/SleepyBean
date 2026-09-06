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

        let sessionsByBaby = Dictionary(grouping: sessions) { $0.baby?.id }
        let feedsByBaby = Dictionary(grouping: feeds) { $0.baby?.id }

        return SleepyBeanBackupFile(
            version: 1,
            exportedAt: Date(),
            babies: babies.map { baby in
                let babySessions = sessionsByBaby[baby.id] ?? baby.sleepSessions
                let babyFeeds = feedsByBaby[baby.id] ?? baby.feedEntries

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

    /// Legacy helper kept for callers that already have baby objects loaded.
    static func makeBackup(from babies: [BabyProfile]) -> SleepyBeanBackupFile {
        SleepyBeanBackupFile(
            version: 1,
            exportedAt: Date(),
            babies: babies.map { baby in
                BabyBackup(
                    id: baby.id,
                    name: baby.name,
                    birthDate: baby.birthDate,
                    createdAt: baby.createdAt,
                    sleepSessions: baby.sleepSessions.map { session in
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
                    feedEntries: baby.feedEntries.map { entry in
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

    static func restore(_ backup: SleepyBeanBackupFile, into context: ModelContext) throws {
        let existingSessions = try context.fetch(FetchDescriptor<SleepSession>())
        for session in existingSessions {
            context.delete(session)
        }
        let existingFeeds = try context.fetch(FetchDescriptor<FeedEntry>())
        for feed in existingFeeds {
            context.delete(feed)
        }
        let existingBabies = try context.fetch(FetchDescriptor<BabyProfile>())
        for baby in existingBabies {
            context.delete(baby)
        }
        try context.save()

        for babyBackup in backup.babies {
            let baby = BabyProfile(name: babyBackup.name, birthDate: babyBackup.birthDate)
            baby.id = babyBackup.id
            baby.createdAt = babyBackup.createdAt
            context.insert(baby)

            for sessionBackup in babyBackup.sleepSessions {
                let session = SleepSession(
                    startTime: sessionBackup.startTime,
                    endTime: sessionBackup.endTime,
                    sleepType: SleepType(rawValue: sessionBackup.sleepType) ?? .nap,
                    notes: sessionBackup.notes
                )
                session.id = sessionBackup.id
                session.pausedAt = sessionBackup.pausedAt
                session.pauseAccumulated = sessionBackup.pauseAccumulated ?? 0
                session.baby = baby
                context.insert(session)
                baby.sleepSessions.append(session)
            }

            for feedBackup in babyBackup.feedEntries {
                let entry = FeedEntry(timestamp: feedBackup.timestamp, side: FeedSide(rawValue: feedBackup.side) ?? .left)
                entry.id = feedBackup.id
                entry.baby = baby
                context.insert(entry)
                baby.feedEntries.append(entry)
            }
        }

        try context.save()
    }

    static func summary(of backup: SleepyBeanBackupFile) -> (babies: Int, sessions: Int, feeds: Int) {
        let sessions = backup.babies.reduce(0) { $0 + $1.sleepSessions.count }
        let feeds = backup.babies.reduce(0) { $0 + $1.feedEntries.count }
        return (backup.babies.count, sessions, feeds)
    }
}
