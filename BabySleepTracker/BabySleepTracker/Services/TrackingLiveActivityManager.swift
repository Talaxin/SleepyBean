import ActivityKit
import Foundation

@MainActor
enum TrackingLiveActivityManager {
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func sync(for baby: BabyProfile) async {
        let activeSession = baby.sleepSessions.first(where: \.isActive)
        await syncActiveSession(babyName: baby.name, session: activeSession)
    }

    static func syncActiveSession(babyName: String, session: SleepSession?) async {
        await endAll()

        guard AppPreferences.liveActivitiesEnabled else { return }
        guard let session, session.isActive else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities disabled in system settings")
            return
        }

        let attributes = TrackingActivityAttributes(
            babyName: babyName,
            sessionType: session.type.rawValue,
            startTime: session.startTime
        )
        let state = TrackingActivityAttributes.ContentState(
            statusLabel: statusLabel(for: session.type)
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    static func endAll() async {
        for activity in Activity<TrackingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func start(
        babyName: String,
        sessionType: SleepType,
        startTime: Date = Date()
    ) {
        Task {
            await syncActiveSession(
                babyName: babyName,
                session: SleepSession(startTime: startTime, sleepType: sessionType)
            )
        }
    }

    static func end() {
        Task {
            await endAll()
        }
    }

    static func restoreIfNeeded(for session: SleepSession, babyName: String) {
        Task {
            await syncActiveSession(babyName: babyName, session: session)
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
