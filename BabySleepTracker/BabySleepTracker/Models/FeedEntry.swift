import Foundation
import SwiftData

enum FeedSide: String, Codable, CaseIterable {
    case left = "Left"
    case right = "Right"
    case bottle = "Bottle"

    var icon: String {
        switch self {
        case .left: return "l.circle.fill"
        case .right: return "r.circle.fill"
        case .bottle: return "waterbottle.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "L"
        case .right: return "R"
        case .bottle: return "Bottle"
        }
    }
}

@Model
final class FeedEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var side: String = FeedSide.left.rawValue

    var baby: BabyProfile?

    init(timestamp: Date = Date(), side: FeedSide) {
        self.id = UUID()
        self.timestamp = timestamp
        self.side = side.rawValue
    }

    var feedSide: FeedSide {
        get { FeedSide(rawValue: side) ?? .left }
        set { side = newValue.rawValue }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
