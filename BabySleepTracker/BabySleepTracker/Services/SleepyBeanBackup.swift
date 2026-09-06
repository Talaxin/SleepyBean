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
}

struct FeedEntryBackup: Codable {
    var id: UUID
    var timestamp: Date
    var side: String
}

enum SleepyBeanBackupEncoder {
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
                            notes: session.notes
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
        let existingBabies = try context.fetch(FetchDescriptor<BabyProfile>())
        for baby in existingBabies {
            context.delete(baby)
        }

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
                session.baby = baby
                context.insert(session)
            }

            for feedBackup in babyBackup.feedEntries {
                let entry = FeedEntry(timestamp: feedBackup.timestamp, side: FeedSide(rawValue: feedBackup.side) ?? .left)
                entry.id = feedBackup.id
                entry.baby = baby
                context.insert(entry)
            }
        }

        try context.save()
    }
}
