import SwiftUI

struct WakeWindowCard: View {
    let readiness: WakeWindowCalculator.NapReadiness
    let guidance: WakeWindowCalculator.Guidance
    let ageInMonths: Int
    let lastWakeTime: Date?
    var now: Date = Date()

    private var accentColor: Color {
        switch readiness {
        case .sleeping: return AppTheme.sleepPurple
        case .justWoke: return .blue
        case .approaching: return .orange
        case .ready: return .green
        case .overtired: return .red
        }
    }

    private var progress: Double {
        guard let lastWake = lastWakeTime else { return 0 }
        let minutesAwake = Int(now.timeIntervalSince(lastWake) / 60)
        return WakeWindowCalculator.progressTowardNap(minutesAwake: minutesAwake, ageInMonths: ageInMonths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: readiness.icon)
                    .font(.title3)
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readiness.title)
                        .font(.subheadline.weight(.semibold))
                    Text(readiness.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if case .sleeping = readiness {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Wake window")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(guidance.rangeDescription)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemFill))
                                .frame(height: 6)
                            Capsule()
                                .fill(accentColor.gradient)
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut(duration: 0.5), value: progress)
                        }
                    }
                    .frame(height: 6)

                    Text("\(guidance.label) · typical window")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        WakeWindowCard(
            readiness: .ready(minutesAwake: 95),
            guidance: WakeWindowCalculator.guidance(forAgeInMonths: 4),
            ageInMonths: 4,
            lastWakeTime: Date().addingTimeInterval(-95 * 60)
        )
        WakeWindowCard(
            readiness: .sleeping,
            guidance: WakeWindowCalculator.guidance(forAgeInMonths: 4),
            ageInMonths: 4,
            lastWakeTime: nil
        )
    }
    .padding()
}
