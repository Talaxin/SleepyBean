import Foundation

/// Age-based wake window guidance from typical pediatric sleep ranges.
struct WakeWindowCalculator {
    struct Guidance {
        let minMinutes: Int
        let maxMinutes: Int
        let label: String

        var rangeDescription: String {
            if minMinutes == maxMinutes {
                return "\(minMinutes) min"
            }
            return "\(minMinutes)–\(maxMinutes) min"
        }
    }

    static func guidance(forAgeInMonths months: Int) -> Guidance {
        switch months {
        case 0...1:
            return Guidance(minMinutes: 45, maxMinutes: 60, label: "Newborn")
        case 2...3:
            return Guidance(minMinutes: 60, maxMinutes: 90, label: "2–3 months")
        case 4...5:
            return Guidance(minMinutes: 90, maxMinutes: 120, label: "4–5 months")
        case 6...8:
            return Guidance(minMinutes: 120, maxMinutes: 150, label: "6–8 months")
        case 9...11:
            return Guidance(minMinutes: 150, maxMinutes: 180, label: "9–11 months")
        case 12...17:
            return Guidance(minMinutes: 180, maxMinutes: 240, label: "12–17 months")
        default:
            return Guidance(minMinutes: 240, maxMinutes: 300, label: "18+ months")
        }
    }

    enum NapReadiness {
        case sleeping
        case justWoke(minutesAgo: Int)
        case approaching(minutesAwake: Int, targetMin: Int, targetMax: Int)
        case ready(minutesAwake: Int)
        case overtired(minutesAwake: Int, overBy: Int)

        var title: String {
            switch self {
            case .sleeping: return "Currently sleeping"
            case .justWoke: return "Just woke up"
            case .approaching: return "Nap window approaching"
            case .ready: return "Good time for a nap"
            case .overtired: return "May be overtired"
            }
        }

        var subtitle: String {
            switch self {
            case .sleeping:
                return "Tap Wake Up when baby stirs"
            case .justWoke(let minutes):
                return "Awake for \(minutes) min — enjoy the calm"
            case .approaching(let awake, let min, let max):
                return "Awake \(awake) min · Nap window \(min)–\(max) min"
            case .ready(let awake):
                return "Awake \(awake) min — good time for a nap"
            case .overtired(let awake, let over):
                return "Awake \(awake) min · \(over) min past ideal window"
            }
        }

        var icon: String {
            switch self {
            case .sleeping: return "moon.zzz.fill"
            case .justWoke: return "sunrise.fill"
            case .approaching: return "clock.fill"
            case .ready: return "sparkles"
            case .overtired: return "exclamationmark.triangle.fill"
            }
        }
    }

    static func napReadiness(
        activeSession: SleepSession?,
        lastCompletedSession: SleepSession?,
        ageInMonths: Int
    ) -> NapReadiness {
        if let active = activeSession, active.isActive {
            return .sleeping
        }

        guard let lastWake = lastCompletedSession?.endTime else {
            return .justWoke(minutesAgo: 0)
        }

        let guidance = guidance(forAgeInMonths: ageInMonths)
        let minutesAwake = max(0, Int(Date().timeIntervalSince(lastWake) / 60))

        if minutesAwake < 15 {
            return .justWoke(minutesAgo: minutesAwake)
        } else if minutesAwake < guidance.minMinutes {
            return .approaching(
                minutesAwake: minutesAwake,
                targetMin: guidance.minMinutes,
                targetMax: guidance.maxMinutes
            )
        } else if minutesAwake <= guidance.maxMinutes {
            return .ready(minutesAwake: minutesAwake)
        } else {
            return .overtired(minutesAwake: minutesAwake, overBy: minutesAwake - guidance.maxMinutes)
        }
    }

    static func progressTowardNap(minutesAwake: Int, ageInMonths: Int) -> Double {
        let guidance = guidance(forAgeInMonths: ageInMonths)
        let target = Double(guidance.maxMinutes)
        guard target > 0 else { return 0 }
        return min(1.0, Double(minutesAwake) / target)
    }
}
