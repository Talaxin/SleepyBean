import Foundation
import SwiftData
import SwiftUI

enum SleepType: String, Codable, CaseIterable {
    case nap = "Nap"
    case night = "Night"
    case awake = "Awake"

    var icon: String {
        switch self {
        case .nap: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        case .awake: return "eyes"
        }
    }

    var accentColor: Color {
        switch self {
        case .nap: return AppTheme.sleepPurple
        case .night: return .indigo
        case .awake: return AppTheme.wakeCoral
        }
    }
}

enum TrackingMode: String, CaseIterable {
    case daytime
    case nighttime

    var title: String {
        switch self {
        case .daytime: return "Daytime"
        case .nighttime: return "Nighttime"
        }
    }

    var primarySessionType: SleepType {
        switch self {
        case .daytime: return .nap
        case .nighttime: return .awake
        }
    }

    var toggleIcon: String {
        switch self {
        case .daytime: return "moon.stars.fill"
        case .nighttime: return "sun.max.fill"
        }
    }

    var toggleLabel: String {
        switch self {
        case .daytime: return "Night"
        case .nighttime: return "Day"
        }
    }
}

@Model
final class SleepSession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var sleepType: String = SleepType.nap.rawValue
    var notes: String = ""

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
