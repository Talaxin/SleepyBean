import SwiftUI

struct FeedingCard: View {
    @Bindable var baby: BabyProfile
    let now: Date
    let onLogFeed: (FeedSide) -> Void

    private var lastFeed: FeedEntry? {
        baby.feedEntries
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private var todayFeeds: [FeedEntry] {
        let calendar = Calendar.current
        return baby.feedEntries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Feeding", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(Color.pink)
                Spacer()
                if !todayFeeds.isEmpty {
                    Text("\(todayFeeds.count) today")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastFeed {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.pink.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: lastFeed.feedSide.icon)
                            .foregroundStyle(.pink)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last feed · \(lastFeed.feedSide.rawValue)")
                            .font(.subheadline.weight(.semibold))
                        Text(SleepFormatter.formatFeedSummary(lastFeed.timestamp, now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            } else {
                Text("No feeds logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(FeedSide.allCases, id: \.self) { side in
                    Button {
                        onLogFeed(side)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: side.icon)
                                .font(.title3)
                            Text(side == .bottle ? "Bottle" : side.shortLabel)
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.pink.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.cardBackground)
        )
    }
}

#Preview {
    FeedingCard(
        baby: BabyProfile(name: "Luna", birthDate: Date()),
        now: Date(),
        onLogFeed: { _ in }
    )
    .padding()
}
