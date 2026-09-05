import ActivityKit
import SwiftUI
import WidgetKit

struct TrackingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(accentColor(for: context.attributes.sessionType).opacity(0.18))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.babyName)
                            .font(.headline)
                        Text(context.state.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(for: context.attributes.startTime)
                        .font(.title3.bold().monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: TrackingActivityIcon.systemName(for: context.attributes.sessionType))
                        Text("SleepyBean")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: TrackingActivityIcon.systemName(for: context.attributes.sessionType))
                    .foregroundStyle(accentColor(for: context.attributes.sessionType))
            } compactTrailing: {
                timerText(for: context.attributes.startTime)
                    .font(.caption.bold().monospacedDigit())
            } minimal: {
                Image(systemName: TrackingActivityIcon.systemName(for: context.attributes.sessionType))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TrackingActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor(for: context.attributes.sessionType).opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: TrackingActivityIcon.systemName(for: context.attributes.sessionType))
                    .foregroundStyle(accentColor(for: context.attributes.sessionType))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.babyName)
                    .font(.headline)
                Text(context.state.statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            timerText(for: context.attributes.startTime)
                .font(.title2.bold().monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 4)
    }

    private func timerText(for startTime: Date) -> Text {
        Text(startTime, style: .timer)
    }

    private func accentColor(for sessionType: String) -> Color {
        switch sessionType {
        case "Nap":
            return Color(red: 0.45, green: 0.35, blue: 0.78)
        case "Awake":
            return Color(red: 0.95, green: 0.55, blue: 0.45)
        case "Night":
            return .indigo
        default:
            return .purple
        }
    }
}
