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
}
