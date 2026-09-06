import ActivityKit
import Foundation

struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusLabel: String
        var timerStart: Date?
        var isPaused: Bool
        var frozenDuration: TimeInterval

        init(
            statusLabel: String,
            timerStart: Date? = nil,
            isPaused: Bool = false,
            frozenDuration: TimeInterval = 0
        ) {
            self.statusLabel = statusLabel
            self.timerStart = timerStart
            self.isPaused = isPaused
            self.frozenDuration = frozenDuration
        }

        enum CodingKeys: String, CodingKey {
            case statusLabel, timerStart, isPaused, frozenDuration
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            statusLabel = try container.decode(String.self, forKey: .statusLabel)
            timerStart = try container.decodeIfPresent(Date.self, forKey: .timerStart)
            isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            frozenDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .frozenDuration) ?? 0
        }
    }

    var babyName: String
    var sessionType: String
    var startTime: Date
}

enum TrackingActivityIcon {
    static func systemName(for sessionType: String) -> String {
        switch sessionType {
        case "Nap": return "moon.zzz.fill"
        case "Awake": return "sun.max.fill"
        case "Night": return "moon.stars.fill"
        default: return "moon.fill"
        }
    }
}

enum TrackingActivityFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
