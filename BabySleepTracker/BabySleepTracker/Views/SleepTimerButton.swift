import SwiftUI

struct SleepTimerButton: View {
    let isSleeping: Bool
    let elapsed: TimeInterval
    let sleepType: SleepType
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(
                            (isSleeping ? AppTheme.sleepPurple : AppTheme.wakePeach).opacity(0.2),
                            lineWidth: 8
                        )
                        .frame(width: 200, height: 200)

                    if isSleeping {
                        Circle()
                            .trim(from: 0, to: min(1, elapsed / (3 * 3600)))
                            .stroke(AppTheme.sleepPurple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: elapsed)
                    }

                    VStack(spacing: 8) {
                        Image(systemName: isSleeping ? "moon.zzz.fill" : "moon.fill")
                            .font(.system(size: 40))
                            .symbolEffect(.bounce, value: isSleeping)

                        if isSleeping {
                            Text(SleepFormatter.formatDuration(elapsed))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())

                            Text(sleepType.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Start Sleep")
                                .font(.title3.bold())
                        }
                    }
                    .foregroundStyle(isSleeping ? AppTheme.sleepPurple : .primary)
                }

                Text(isSleeping ? "Tap to Wake Up" : "One tap to begin tracking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = true } }
                .onEnded { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = false } }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isSleeping)
    }
}

#Preview {
    VStack(spacing: 20) {
        SleepTimerButton(isSleeping: false, elapsed: 0, sleepType: .nap) {}
        SleepTimerButton(isSleeping: true, elapsed: 3723, sleepType: .nap) {}
    }
    .padding()
    .background(AppTheme.softBackground)
}
