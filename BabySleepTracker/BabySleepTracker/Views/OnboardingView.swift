import SwiftUI

struct OnboardingView: View {
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    let onComplete: (String, Date) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppTheme.napGradient)
                        .symbolEffect(.pulse, options: .repeating)

                    Text("SleepyBean")
                        .font(.largeTitle.bold())

                    Text("Track naps and night sleep\nwith one tap — just like the pros.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Baby's name")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Luna", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Birth date")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    onComplete(trimmed.isEmpty ? "Baby" : trimmed, birthDate)
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sleepPurple)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .background(AppTheme.softBackground)
        }
    }
}

#Preview {
    OnboardingView { _, _ in }
}
