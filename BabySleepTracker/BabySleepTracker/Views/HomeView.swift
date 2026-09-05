import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var baby: BabyProfile
    @Environment(\.modelContext) private var modelContext

    @State private var now = Date()
    @State private var showAddSleep = false
    @State private var showSleepTypePicker = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var todaySessions: [SleepSession] {
        let calendar = Calendar.current
        return baby.sleepSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: Date()) }
            .sorted { $0.startTime > $1.startTime }
    }

    private var activeSession: SleepSession? {
        baby.sleepSessions.first { $0.isActive }
    }

    private var lastCompletedSession: SleepSession? {
        baby.sleepSessions
            .filter { !$0.isActive }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
            .first
    }

    private var todayStats: DaySleepStats {
        DaySleepStats(sessions: todaySessions.filter { !$0.isActive })
    }

    private var napReadiness: WakeWindowCalculator.NapReadiness {
        WakeWindowCalculator.napReadiness(
            activeSession: activeSession,
            lastCompletedSession: lastCompletedSession,
            ageInMonths: baby.ageInMonths
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    wakeWindowCard
                    sleepTimerSection
                    todayStatsRow
                    timelineSection
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
            .confirmationDialog("Sleep type", isPresented: $showSleepTypePicker, titleVisibility: .visible) {
                Button("Nap") { startSleep(type: .nap) }
                Button("Night Sleep") { startSleep(type: .night) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What kind of sleep?")
            }
            .onReceive(timer) { _ in
                now = Date()
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
            if activeSession != nil {
                LiveBadge()
            }
        }
        .padding(.top, 8)
    }

    private var wakeWindowCard: some View {
        WakeWindowCard(
            readiness: napReadiness,
            guidance: WakeWindowCalculator.guidance(forAgeInMonths: baby.ageInMonths),
            ageInMonths: baby.ageInMonths,
            lastWakeTime: lastCompletedSession?.endTime
        )
    }

    private var sleepTimerSection: some View {
        SleepTimerButton(
            isSleeping: activeSession != nil,
            elapsed: activeSession?.elapsed ?? 0,
            sleepType: activeSession?.type ?? .nap,
            onTap: handleMainButtonTap
        )
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
                title: "Longest",
                value: todayStats.longestNapFormatted,
                icon: "clock.fill",
                color: .teal
            )
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Log")
                .font(.headline)

            if todaySessions.isEmpty {
                EmptyTimelineCard()
            } else {
                ForEach(todaySessions, id: \.id) { session in
                    SleepSessionRow(session: session)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteSession(session)
                            }
                        }
                }
            }
        }
    }

    private func handleMainButtonTap() {
        if let active = activeSession {
            endSleep(active)
        } else {
            showSleepTypePicker = true
        }
    }

    private func startSleep(type: SleepType) {
        let session = SleepSession(startTime: Date(), sleepType: type)
        session.baby = baby
        modelContext.insert(session)
    }

    private func endSleep(_ session: SleepSession) {
        session.endTime = Date()
    }

    private func deleteSession(_ session: SleepSession) {
        modelContext.delete(session)
    }
}

struct DaySleepStats {
    let sessions: [SleepSession]

    var totalSleep: TimeInterval {
        sessions.compactMap(\.duration).reduce(0, +)
    }

    var napCount: Int {
        sessions.filter { $0.type == .nap }.count
    }

    var longestNap: TimeInterval {
        sessions.compactMap(\.duration).max() ?? 0
    }

    var totalSleepFormatted: String {
        SleepFormatter.formatDurationCompact(totalSleep)
    }

    var longestNapFormatted: String {
        longestNap > 0 ? SleepFormatter.formatDurationCompact(longestNap) : "—"
    }
}

struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing ? 1.3 : 1.0)
            Text("Sleeping")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever()) {
                pulsing = true
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BabyProfile.self, SleepSession.self, configurations: config)
    let baby = BabyProfile(name: "Luna", birthDate: Calendar.current.date(byAdding: .month, value: -4, to: Date())!)
    container.mainContext.insert(baby)
    return HomeView(baby: baby)
        .modelContainer(container)
}
