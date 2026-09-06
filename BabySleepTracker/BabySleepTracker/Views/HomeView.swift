import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var baby: BabyProfile
    @Environment(\.modelContext) private var modelContext

    @AppStorage("trackingMode") private var trackingModeRaw = TrackingMode.daytime.rawValue
    @State private var showAddSleep = false
    @State private var showStopConfirmation = false
    @State private var sessionPendingStop: SleepSession?
    @State private var liveNow = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var trackingMode: TrackingMode {
        TrackingMode(rawValue: trackingModeRaw) ?? .daytime
    }

    private var todaySessions: [SleepSession] {
        let calendar = Calendar.current
        return baby.sleepSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: Date()) }
            .sorted { $0.startTime > $1.startTime }
    }

    private var todayFeeds: [FeedEntry] {
        let calendar = Calendar.current
        return baby.feedEntries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: Date()) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var todayLogItems: [TodayLogItem] {
        let sessions = todaySessions.map(TodayLogItem.sleep)
        let feeds = todayFeeds.map(TodayLogItem.feed)
        return (sessions + feeds).sorted { $0.sortDate > $1.sortDate }
    }

    private var activeSession: SleepSession? {
        baby.sleepSessions.first { $0.isActive }
    }

    private var lastCompletedSession: SleepSession? {
        baby.sleepSessions
            .filter { !$0.isActive && $0.type != .awake }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
            .first
    }

    private var todayStats: DaySleepStats {
        DaySleepStats(sessions: todaySessions.filter { !$0.isActive })
    }

    private var napReadiness: WakeWindowCalculator.NapReadiness {
        WakeWindowCalculator.napReadiness(
            activeSession: activeSession?.type == .awake ? nil : activeSession,
            lastCompletedSession: lastCompletedSession,
            ageInMonths: baby.ageInMonths
        )
    }

    private var stopConfirmationTitle: String {
        guard let session = sessionPendingStop else { return "End tracking?" }
        switch session.type {
        case .nap: return "End nap?"
        case .awake: return "Baby fell asleep?"
        case .night: return "End night sleep?"
        }
    }

    private var stopConfirmationMessage: String {
        guard let session = sessionPendingStop else { return "" }
        let elapsed = SleepFormatter.formatDuration(session.elapsed)
        switch session.type {
        case .nap:
            return "This nap has been \(elapsed). End it now?"
        case .awake:
            return "Baby was awake for \(elapsed). Log them as asleep?"
        case .night:
            return "Night sleep has been \(elapsed). End it now?"
        }
    }

    private var stopConfirmationButtonTitle: String {
        guard let session = sessionPendingStop else { return "End" }
        switch session.type {
        case .nap: return "End Nap"
        case .awake: return "Baby's Asleep"
        case .night: return "End Sleep"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    if trackingMode == .daytime {
                        wakeWindowCard
                    }
                    trackingTimerSection
                    feedingSection
                    todayStatsRow
                    timelineSection
                    buildFooter
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(AppTheme.softBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSleep = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showAddSleep) {
                AddSleepView(baby: baby)
            }
            .alert(stopConfirmationTitle, isPresented: $showStopConfirmation) {
                Button(stopConfirmationButtonTitle) {
                    if let session = sessionPendingStop {
                        endSession(session)
                    }
                    sessionPendingStop = nil
                }
                Button("Keep Tracking", role: .cancel) {
                    sessionPendingStop = nil
                }
            } message: {
                Text(stopConfirmationMessage)
            }
            .onReceive(timer) { date in
                liveNow = date
            }
            .onAppear {
                if let active = activeSession {
                    TrackingLiveActivityManager.restoreIfNeeded(for: active, babyName: baby.name)
                }
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(baby.name)
                    .font(.title2.bold())
                Text(baby.ageDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let activeSession {
                LiveBadge(sessionType: activeSession.type, startTime: activeSession.startTime)
            } else {
                ModeBadge(mode: trackingMode)
            }
        }
        .padding(.top, 8)
    }

    private var wakeWindowCard: some View {
        WakeWindowCard(
            readiness: napReadiness,
            guidance: WakeWindowCalculator.guidance(forAgeInMonths: baby.ageInMonths),
            ageInMonths: baby.ageInMonths,
            lastWakeTime: lastCompletedSession?.endTime,
            now: liveNow
        )
    }

    private var trackingTimerSection: some View {
        TrackingTimerCard(
            mode: trackingMode,
            isTracking: activeSession != nil,
            startTime: activeSession?.startTime,
            trackedType: activeSession?.type,
            canToggleMode: activeSession == nil,
            onMainTap: handleMainButtonTap,
            onModeToggle: toggleTrackingMode
        )
    }

    private var feedingSection: some View {
        FeedingCard(baby: baby, now: liveNow) { side in
            logFeed(side)
        }
    }

    private var buildFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return Text("SleepyBean \(version) (\(build))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private var todayStatsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Sleep",
                value: todayStats.totalSleepFormatted,
                icon: "bed.double.fill",
                color: AppTheme.sleepPurple
            )
            StatCard(
                title: "Naps",
                value: "\(todayStats.napCount)",
                icon: "sun.max.fill",
                color: AppTheme.wakeCoral
            )
            StatCard(
                title: trackingMode == .nighttime ? "Awake" : "Longest",
                value: trackingMode == .nighttime ? todayStats.awakeCountFormatted : todayStats.longestNapFormatted,
                icon: trackingMode == .nighttime ? "eyes" : "clock.fill",
                color: .teal
            )
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Log")
                .font(.headline)

            if todayLogItems.isEmpty {
                EmptyTimelineCard(mode: trackingMode)
            } else {
                ForEach(todayLogItems) { item in
                    switch item {
                    case .sleep(let session):
                        SleepSessionRow(session: session, now: liveNow)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteSession(session)
                                }
                            }
                    case .feed(let entry):
                        FeedEntryRow(entry: entry, now: liveNow)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteFeed(entry)
                                }
                            }
                    }
                }
            }
        }
    }

    private func handleMainButtonTap() {
        if let active = activeSession {
            sessionPendingStop = active
            showStopConfirmation = true
        } else {
            startTracking(for: trackingMode.primarySessionType)
        }
    }

    private func toggleTrackingMode() {
        guard activeSession == nil else { return }
        trackingModeRaw = (trackingMode == .daytime ? TrackingMode.nighttime : .daytime).rawValue
    }

    private func startTracking(for type: SleepType) {
        let session = SleepSession(startTime: Date(), sleepType: type)
        session.baby = baby
        modelContext.insert(session)
        TrackingLiveActivityManager.start(babyName: baby.name, sessionType: type, startTime: session.startTime)
    }

    private func endSession(_ session: SleepSession) {
        session.endTime = Date()
        TrackingLiveActivityManager.end()
    }

    private func logFeed(_ side: FeedSide) {
        let entry = FeedEntry(side: side)
        entry.baby = baby
        modelContext.insert(entry)
    }

    private func deleteSession(_ session: SleepSession) {
        if session.isActive {
            TrackingLiveActivityManager.end()
        }
        modelContext.delete(session)
    }

    private func deleteFeed(_ entry: FeedEntry) {
        modelContext.delete(entry)
    }
}

private enum TodayLogItem: Identifiable {
    case sleep(SleepSession)
    case feed(FeedEntry)

    var id: UUID {
        switch self {
        case .sleep(let session): return session.id
        case .feed(let entry): return entry.id
        }
    }

    var sortDate: Date {
        switch self {
        case .sleep(let session): return session.startTime
        case .feed(let entry): return entry.timestamp
        }
    }
}

struct DaySleepStats {
    let sessions: [SleepSession]

    var totalSleep: TimeInterval {
        sessions
            .filter { $0.type == .nap || $0.type == .night }
            .compactMap(\.duration)
            .reduce(0, +)
    }

    var napCount: Int {
        sessions.filter { $0.type == .nap }.count
    }

    var awakeCount: Int {
        sessions.filter { $0.type == .awake }.count
    }

    var longestNap: TimeInterval {
        sessions.filter { $0.type == .nap }.compactMap(\.duration).max() ?? 0
    }

    var totalSleepFormatted: String {
        SleepFormatter.formatDurationCompact(totalSleep)
    }

    var longestNapFormatted: String {
        longestNap > 0 ? SleepFormatter.formatDurationCompact(longestNap) : "—"
    }

    var awakeCountFormatted: String {
        awakeCount > 0 ? "\(awakeCount)" : "—"
    }
}

struct LiveBadge: View {
    let sessionType: SleepType
    let startTime: Date

    @State private var pulsing = false

    private var label: String {
        switch sessionType {
        case .nap: return "Napping"
        case .awake: return "Awake"
        case .night: return "Sleeping"
        }
    }

    private var color: Color {
        sessionType.accentColor
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = SleepFormatter.formatDuration(context.date.timeIntervalSince(startTime))

            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsing ? 1.3 : 1.0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(elapsed)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever()) {
                pulsing = true
            }
        }
    }
}

struct ModeBadge: View {
    let mode: TrackingMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .daytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.caption)
            Text(mode.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(mode == .daytime ? AppTheme.wakeCoral : .indigo)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((mode == .daytime ? AppTheme.wakeCoral : Color.indigo).opacity(0.12))
        .clipShape(Capsule())
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BabyProfile.self, SleepSession.self, FeedEntry.self, configurations: config)
    let baby = BabyProfile(name: "Luna", birthDate: Calendar.current.date(byAdding: .month, value: -4, to: Date())!)
    container.mainContext.insert(baby)
    return HomeView(baby: baby)
        .modelContainer(container)
}
