import ActivityKit
import Foundation

@MainActor
enum TrackingLiveActivityManager {
    private static var currentActivity: Activity<TrackingActivityAttributes>?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(
        babyName: String,
        sessionType: SleepType,
        startTime: Date = Date()
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        end()

        let attributes = TrackingActivityAttributes(
            babyName: babyName,
            sessionType: sessionType.rawValue,
            startTime: startTime
        )
        let state = TrackingActivityAttributes.ContentState(
            statusLabel: statusLabel(for: sessionType)
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    static func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func restoreIfNeeded(for session: SleepSession, babyName: String) {
        guard session.isActive else { return }
        if currentActivity == nil {
            start(babyName: babyName, sessionType: session.type, startTime: session.startTime)
        }
    }

    private static func statusLabel(for type: SleepType) -> String {
        switch type {
        case .nap: return "Napping"
        case .awake: return "Awake"
        case .night: return "Sleeping"
        }
    }
}
