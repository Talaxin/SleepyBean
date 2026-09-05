import SwiftUI
import SwiftData

struct HistoryView: View {
    @Bindable var baby: BabyProfile
    @State private var selectedDate = Date()

    private var groupedSessions: [(date: Date, sessions: [SleepSession], stats: DaySleepStats)] {
        let calendar = Calendar.current
        let completed = baby.sleepSessions.filter { !$0.isActive }

        let grouped = Dictionary(grouping: completed) { session in
            calendar.startOfDay(for: session.startTime)
        }

        return grouped
            .map { (date: $0.key, sessions: $0.value.sorted { $0.startTime > $1.startTime }, stats: DaySleepStats(sessions: $0.value)) }
            .sorted { $0.date > $1.date }
    }

    private var selectedDaySessions: [SleepSession] {
        let calendar = Calendar.current
        return baby.sleepSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: selectedDate) && !$0.isActive }
            .sorted { $0.startTime < $1.startTime }
    }

    private var selectedDayStats: DaySleepStats {
        DaySleepStats(sessions: selectedDaySessions)
    }

    private var last7DaysData: [(date: Date, hours: Double)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))!
            let sessions = baby.sleepSessions.filter {
                calendar.isDate($0.startTime, inSameDayAs: date) && !$0.isActive
            }
            let totalHours = sessions.compactMap(\.duration).reduce(0, +) / 3600
            return (date: date, hours: totalHours)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    weekChart
                    datePicker
                    dayDetail
                    pastDaysList
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(AppTheme.softBackground)
            .navigationTitle("History")
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7DaysData, id: \.date) { item in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                Calendar.current.isDate(item.date, inSameDayAs: selectedDate)
                                    ? AppTheme.sleepPurple
                                    : AppTheme.sleepPurple.opacity(0.35)
                            )
                            .frame(height: max(4, CGFloat(item.hours / 16) * 120))

                        Text(dayLabel(item.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation { selectedDate = item.date }
                    }
                }
            }
            .frame(height: 150)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
        }
    }

    private var datePicker: some View {
        DatePicker(
            "Select day",
            selection: $selectedDate,
            in: ...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardBackground)
        )
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SleepFormatter.formatDayHeader(selectedDate))
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(
                    title: "Total",
                    value: selectedDayStats.totalSleepFormatted,
                    icon: "bed.double.fill",
                    color: AppTheme.sleepPurple
                )
                StatCard(
                    title: "Naps",
                    value: "\(selectedDayStats.napCount)",
                    icon: "sun.max.fill",
                    color: AppTheme.wakeCoral
                )
                StatCard(
                    title: "Sessions",
                    value: "\(selectedDaySessions.count)",
                    icon: "list.bullet",
                    color: .teal
                )
            }

            if selectedDaySessions.isEmpty {
                Text("No sleep logged this day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.cardBackground)
                    )
            } else {
                ForEach(selectedDaySessions, id: \.id) { session in
                    SleepSessionRow(session: session)
                }
            }
        }
    }

    private var pastDaysList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if groupedSessions.count > 1 {
                Text("All Days")
                    .font(.headline)

                ForEach(groupedSessions.prefix(14), id: \.date) { group in
                    Button {
                        selectedDate = group.date
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SleepFormatter.formatDayHeader(group.date))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("\(group.sessions.count) session\(group.sessions.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(group.stats.totalSleepFormatted)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.sleepPurple)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.cardBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

#Preview {
    let baby = BabyProfile(name: "Luna", birthDate: Date())
    return HistoryView(baby: baby)
}
