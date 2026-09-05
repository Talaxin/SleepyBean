import ActivityKit
import Foundation

struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusLabel: String
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
