import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardBackground)
        )
    }
}

struct FeedEntryRow: View {
    let entry: FeedEntry
    var now: Date = Date()

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: entry.feedSide.icon)
                    .foregroundStyle(.pink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Feed · \(entry.feedSide.rawValue)")
                    .font(.subheadline.weight(.semibold))
                Text(SleepFormatter.formatFeedSummary(entry.timestamp, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.formattedTime)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.pink)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardBackground)
        )
    }
}

struct SleepSessionRow: View {
    let session: SleepSession
    var now: Date = Date()
    @State private var showEdit = false

    private var displayDuration: String {
        if session.isActive {
            return SleepFormatter.formatDuration(now.timeIntervalSince(session.startTime))
        }
        return session.formattedDuration
    }

    var body: some View {
        Button {
            showEdit = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(session.type.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: session.type.icon)
                        .foregroundStyle(session.type.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.type.rawValue)
                            .font(.subheadline.weight(.semibold))
                        if session.isActive {
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(session.formattedTimeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Group {
                    if session.isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(SleepFormatter.formatDuration(context.date.timeIntervalSince(session.startTime)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(session.type.accentColor)
                        }
                    } else {
                        Text(displayDuration)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(session.type.accentColor)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEdit) {
            EditSleepView(session: session)
        }
    }
}

struct EmptyTimelineCard: View {
    var mode: TrackingMode = .daytime

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: mode == .daytime ? "moon.zzz" : "moon.stars")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No activity logged yet today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(mode == .daytime
                 ? "Tap the big button to start a nap, or log a feed below"
                 : "Tap the big button when baby wakes up, or log a feed below")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardBackground)
        )
    }
}

#Preview {
    VStack {
        HStack {
            StatCard(title: "Total Sleep", value: "4h 20m", icon: "bed.double.fill", color: .purple)
            StatCard(title: "Naps", value: "3", icon: "sun.max.fill", color: .orange)
        }
    }
    .padding()
}
