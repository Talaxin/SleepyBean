import SwiftUI

struct TrackingTimerCard: View {
    let mode: TrackingMode
    let isTracking: Bool
    let startTime: Date?
    let trackedType: SleepType?
    let canToggleMode: Bool
    let onMainTap: () -> Void
    let onModeToggle: () -> Void

    private var accentColor: Color {
        if isTracking, let trackedType {
            return trackedType.accentColor
        }
        return mode == .daytime ? AppTheme.sleepPurple : AppTheme.wakeCoral
    }

    private var idleIcon: String {
        mode == .daytime ? "moon.zzz.fill" : "sun.max.fill"
    }

    private var idleTitle: String {
        mode == .daytime ? "Start Nap" : "Start Awake"
    }

    private var trackingHint: String {
        switch trackedType {
        case .nap: return "Tap to end nap"
        case .awake: return "Tap when baby falls asleep"
        case .night: return "Tap to end sleep"
        case .none: return ""
        }
    }

    private var idleHint: String {
        mode == .daytime
            ? "Big button tracks naps"
            : "Big button tracks awake time"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = elapsedDuration(at: context.date)

                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.2), lineWidth: 8)
                            .frame(width: 200, height: 200)

                        if isTracking {
                            Circle()
                                .trim(from: 0, to: min(1, elapsed / progressCap))
                                .stroke(accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 200, height: 200)
                                .rotationEffect(.degrees(-90))
                        }

                        VStack(spacing: 8) {
                            Image(systemName: isTracking ? (trackedType?.icon ?? idleIcon) : idleIcon)
                                .font(.system(size: 40))
                                .symbolEffect(.bounce, value: isTracking)

                            if isTracking {
                                Text(SleepFormatter.formatDuration(elapsed))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(.default, value: elapsed)

                                Text(trackedType?.rawValue ?? mode.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(idleTitle)
                                    .font(.title3.bold())
                            }
                        }
                        .foregroundStyle(isTracking ? accentColor : .primary)
                    }
                }

                Text(isTracking ? trackingHint : idleHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isTracking ? trackingHint : idleTitle)
            .onTapGesture {
                onMainTap()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isTracking)

            Button(action: onModeToggle) {
                VStack(spacing: 4) {
                    Image(systemName: mode.toggleIcon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(mode.toggleLabel)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            mode == .daytime
                                ? LinearGradient(colors: [.indigo, Color(red: 0.3, green: 0.2, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [AppTheme.wakePeach, AppTheme.wakeCoral], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canToggleMode)
            .opacity(canToggleMode ? 1 : 0.45)
            .padding(14)
            .accessibilityLabel("Switch to \(mode == .daytime ? "nighttime" : "daytime") mode")
        }
    }

    private var progressCap: TimeInterval {
        switch trackedType {
        case .awake: return 90 * 60
        case .night: return 12 * 3600
        default: return 3 * 3600
        }
    }

    private func elapsedDuration(at date: Date) -> TimeInterval {
        guard let startTime else { return 0 }
        return max(0, date.timeIntervalSince(startTime))
    }
}

#Preview {
    VStack(spacing: 20) {
        TrackingTimerCard(
            mode: .daytime,
            isTracking: false,
            startTime: nil,
            trackedType: nil,
            canToggleMode: true,
            onMainTap: {},
            onModeToggle: {}
        )
        TrackingTimerCard(
            mode: .daytime,
            isTracking: true,
            startTime: Date().addingTimeInterval(-3723),
            trackedType: .nap,
            canToggleMode: false,
            onMainTap: {},
            onModeToggle: {}
        )
        TrackingTimerCard(
            mode: .nighttime,
            isTracking: true,
            startTime: Date().addingTimeInterval(-842),
            trackedType: .awake,
            canToggleMode: false,
            onMainTap: {},
            onModeToggle: {}
        )
    }
    .padding()
    .background(AppTheme.softBackground)
}
