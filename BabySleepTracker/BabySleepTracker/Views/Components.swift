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

struct SleepSessionRow: View {
    let session: SleepSession
    @State private var showEdit = false

    var body: some View {
        Button {
            showEdit = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(session.type == .nap ? AppTheme.sleepPurple.opacity(0.15) : Color.indigo.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: session.type.icon)
                        .foregroundStyle(session.type == .nap ? AppTheme.sleepPurple : .indigo)
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

                Text(session.formattedDuration)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.sleepPurple)

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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No sleep logged yet today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap the big button above to start tracking")
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
