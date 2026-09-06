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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.babyName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerView(context: context, font: .title3.bold().monospacedDigit())
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor(for: context.attributes.sessionType))
                    .frame(width: 18, height: 18)
                    .fixedSize()
            } compactTrailing: {
                timerView(context: context, font: .caption2.bold().monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .fixedSize()
            } minimal: {
                Image(systemName: TrackingActivityIcon.systemName(for: context.attributes.sessionType))
                    .foregroundStyle(accentColor(for: context.attributes.sessionType))
            }
            .keylineTint(accentColor(for: context.attributes.sessionType))
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

            timerView(context: context, font: .title2.bold().monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func timerView(
        context: ActivityViewContext<TrackingActivityAttributes>,
        font: Font
    ) -> some View {
        let start = context.state.timerStart ?? context.attributes.startTime
        if context.state.isPaused {
            Text(TrackingActivityFormatting.duration(context.state.frozenDuration))
                .font(font)
                .monospacedDigit()
        } else {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
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
