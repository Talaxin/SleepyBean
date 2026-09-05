import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var babies: [BabyProfile]
    @State private var selectedBaby: BabyProfile?
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if let baby = selectedBaby ?? babies.first {
                MainTabView(baby: baby, allBabies: babies)
            } else {
                OnboardingView { name, birthDate in
                    let baby = BabyProfile(name: name, birthDate: birthDate)
                    modelContext.insert(baby)
                    selectedBaby = baby
                }
            }
        }
        .onAppear {
            if babies.isEmpty {
                showOnboarding = true
            } else {
                selectedBaby = babies.first
            }
        }
    }
}

struct MainTabView: View {
    let baby: BabyProfile
    let allBabies: [BabyProfile]

    var body: some View {
        TabView {
            HomeView(baby: baby)
                .tabItem {
                    Label("Today", systemImage: "moon.stars.fill")
                }

            HistoryView(baby: baby)
                .tabItem {
                    Label("History", systemImage: "chart.bar.fill")
                }

            SettingsView(baby: baby, allBabies: allBabies)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(AppTheme.sleepPurple)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BabyProfile.self, SleepSession.self], inMemory: true)
}
