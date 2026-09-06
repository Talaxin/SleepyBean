import Foundation
import SwiftData

@Model
final class BabyProfile {
    var id: UUID = UUID()
    var name: String = ""
    var birthDate: Date = Date()
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SleepSession.baby)
    var sleepSessions: [SleepSession] = []

    @Relationship(deleteRule: .cascade, inverse: \FeedEntry.baby)
    var feedEntries: [FeedEntry] = []

    init(name: String, birthDate: Date) {
        self.id = UUID()
        self.name = name
        self.birthDate = birthDate
        self.createdAt = Date()
    }

    var ageInMonths: Int {
        let components = Calendar.current.dateComponents([.month], from: birthDate, to: Date())
        return max(components.month ?? 0, 0)
    }

    var ageDescription: String {
        let months = ageInMonths
        if months < 1 {
            let days = Calendar.current.dateComponents([.day], from: birthDate, to: Date()).day ?? 0
            return "\(days) days old"
        } else if months < 24 {
            return "\(months) month\(months == 1 ? "" : "s") old"
        } else {
            let years = months / 12
            let remainingMonths = months % 12
            if remainingMonths == 0 {
                return "\(years) year\(years == 1 ? "" : "s") old"
            }
        return "\(years)y \(remainingMonths)m old"
        }
    }

    @MainActor
    static func mergeDuplicates(in context: ModelContext, babies: [BabyProfile]) {
        let calendar = Calendar.current
        var groups: [String: [BabyProfile]] = [:]
        for baby in babies {
            let name = baby.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let day = calendar.startOfDay(for: baby.birthDate)
            let key = "\(name)|\(Int(day.timeIntervalSince1970))"
            groups[key, default: []].append(baby)
        }

        for group in groups.values where group.count > 1 {
            let keeper = group.max { lhs, rhs in
                let leftCount = lhs.sleepSessions.count + lhs.feedEntries.count
                let rightCount = rhs.sleepSessions.count + rhs.feedEntries.count
                if leftCount != rightCount {
                    return leftCount < rightCount
                }
                return lhs.createdAt > rhs.createdAt
            }!

            for duplicate in group where duplicate.id != keeper.id {
                for session in duplicate.sleepSessions {
                    if !keeper.sleepSessions.contains(where: { $0.id == session.id }) {
                        session.baby = keeper
                    }
                }
                for feed in duplicate.feedEntries {
                    if !keeper.feedEntries.contains(where: { $0.id == feed.id }) {
                        feed.baby = keeper
                    }
                }
                context.delete(duplicate)
            }
        }

        try? context.save()
    }
}
