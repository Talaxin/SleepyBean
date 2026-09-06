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
    var pausedAt: Date?
    var pauseAccumulated: TimeInterval = 0

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

    var isPaused: Bool {
        pausedAt != nil && endTime == nil
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return max(0, end.timeIntervalSince(startTime) - pauseAccumulated)
    }

    var elapsed: TimeInterval {
        elapsed(at: Date())
    }

    func elapsed(at date: Date) -> TimeInterval {
        let end = endTime ?? pausedAt ?? date
        return max(0, end.timeIntervalSince(startTime) - pauseAccumulated)
    }

    func pause(at date: Date = Date()) {
        guard isActive, pausedAt == nil else { return }
        pausedAt = date
    }

    func resume() {
        guard let pausedAt else { return }
        pauseAccumulated += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    func finish(at date: Date = Date()) {
        if let pausedAt {
            endTime = pausedAt
            self.pausedAt = nil
        } else {
            endTime = date
        }
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
