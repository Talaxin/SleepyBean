import ActivityKit
import Foundation

@MainActor
enum TrackingLiveActivityManager {
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func sync(for baby: BabyProfile) async {
        await present(babyName: baby.name, session: liveSession(for: baby))
    }

    static func liveSession(for baby: BabyProfile) -> SleepSession? {
        switch trackingMode {
        case .daytime:
            return baby.sleepSessions.first { $0.isActive && $0.type == .nap }
        case .nighttime:
            return baby.sleepSessions
                .filter { $0.isActive && $0.type == .night }
                .min(by: { $0.startTime < $1.startTime })
        }
    }

    static func syncActiveSession(babyName: String, session: SleepSession?) async {
        await present(babyName: babyName, session: session)
    }

    static func start(
        babyName: String,
        sessionType: SleepType,
        startTime: Date = Date()
    ) {
        Task {
            await present(
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
            await present(babyName: babyName, session: session)
        }
    }

    static func endAll() async {
        for activity in Activity<TrackingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static var trackingMode: TrackingMode {
        TrackingMode(rawValue: UserDefaults.standard.string(forKey: "trackingMode") ?? "") ?? .daytime
    }

    private static func present(babyName: String, session: SleepSession?) async {
        guard AppPreferences.liveActivitiesEnabled else {
            await endAll()
            return
        }

        guard let session, session.isActive else {
            await endAll()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities disabled in system settings")
            return
        }

        let state = contentState(for: session)
        let sessionType = session.type.rawValue

        if let existing = Activity<TrackingActivityAttributes>.activities.first {
            if existing.attributes.sessionType == sessionType {
                await existing.update(ActivityContent(state: state, staleDate: nil))
                return
            }
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = TrackingActivityAttributes(
            babyName: babyName,
            sessionType: sessionType,
            startTime: session.startTime
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

    private static func contentState(for session: SleepSession) -> TrackingActivityAttributes.ContentState {
        let elapsed = session.elapsed
        return TrackingActivityAttributes.ContentState(
            statusLabel: statusLabel(for: session),
            timerStart: session.startTime.addingTimeInterval(session.pauseAccumulated),
            isPaused: session.isPaused,
            frozenDuration: elapsed
        )
    }

    private static func statusLabel(for session: SleepSession) -> String {
        switch session.type {
        case .nap: return "Napping"
        case .awake: return "Awake"
        case .night: return session.isPaused ? "Sleeping" : "Sleeping"
        }
    }
}
