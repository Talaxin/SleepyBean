import Foundation
import SwiftData

enum SleepType: String, Codable, CaseIterable {
    case nap = "Nap"
    case night = "Night"

    var icon: String {
        switch self {
        case .nap: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

@Model
final class SleepSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var sleepType: String
    var notes: String

    var baby: BabyProfile?

    init(startTime: Date, endTime: Date? = nil, sleepType: SleepType = .nap, notes: String = "") {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.sleepType = sleepType.rawValue
        self.notes = notes
    }

    var type: SleepType {
        get { SleepType(rawValue: sleepType) ?? .nap }
        set { sleepType = newValue.rawValue }
    }

    var isActive: Bool {
        endTime == nil
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var elapsed: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        SleepFormatter.formatDuration(elapsed)
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: startTime)
        if let end = endTime {
            return "\(start) – \(formatter.string(from: end))"
        }
        return "Started \(start)"
    }
}
