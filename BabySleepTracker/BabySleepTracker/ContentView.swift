import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BabyProfile.createdAt) private var babies: [BabyProfile]
    @State private var selectedBabyID: UUID?
    @State private var showOnboarding = false
    @AppStorage("partner.hasShare") private var hasPartnerShare = false

    private let partnerPoll = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private var selectedBaby: BabyProfile? {
        if let selectedBabyID,
           let match = babies.first(where: { $0.id == selectedBabyID }) {
            return match
        }
        return babies.max(by: {
            ($0.sleepSessions.count + $0.feedEntries.count) < ($1.sleepSessions.count + $1.feedEntries.count)
        }) ?? babies.first
    }

    var body: some View {
        Group {
            if let baby = selectedBaby {
                MainTabView(baby: baby, allBabies: babies)
                    .id(baby.id)
            } else {
                OnboardingView { name, birthDate in
                    let baby = BabyProfile(name: name, birthDate: birthDate)
                    modelContext.insert(baby)
                    selectedBabyID = baby.id
                }
            }
        }
        .onOpenURL { url in
            Task {
                await CloudKitSharingCoordinator.shared.acceptShare(from: url)
            }
        }
        .onAppear {
            if babies.isEmpty {
                showOnboarding = true
            } else if selectedBabyID == nil {
                selectedBabyID = selectedBaby?.id
            }
            syncLiveActivities()
            Task {
                BabyProfile.mergeDuplicates(in: modelContext, babies: babies)
                if let selectedBabyID,
                   babies.contains(where: { $0.id == selectedBabyID }) {
                    // keep
                } else {
                    self.selectedBabyID = selectedBaby?.id
                }
                await CloudKitSharingCoordinator.shared.consumePendingShare(modelContext: modelContext)
                if let sharedID = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.babyUUIDKey),
                   let uuid = UUID(uuidString: sharedID),
                   babies.contains(where: { $0.id == uuid }) {
                    selectedBabyID = uuid
                }
            }
        }
        .onChange(of: babies.map(\.id)) { _, _ in
            if let selectedBabyID,
               babies.contains(where: { $0.id == selectedBabyID }) {
                return
            }
            selectedBabyID = selectedBaby?.id
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                syncLiveActivities()
                Task {
                    await CloudKitSharingCoordinator.shared.pullPartnerData(into: modelContext)
                }
            case .background:
                Task {
                    await iCloudBackupService.shared.backupIfPossible(context: modelContext)
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepyBeanDidReceiveShare)) { _ in
            Task {
                await CloudKitSharingCoordinator.shared.pullPartnerData(into: modelContext)
                if let sharedID = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.babyUUIDKey),
                   let uuid = UUID(uuidString: sharedID) {
                    selectedBabyID = uuid
                } else {
                    selectedBabyID = selectedBaby?.id
                }
            }
        }
        .onReceive(partnerPoll) { _ in
            guard scenePhase == .active, hasPartnerShare else { return }
            Task {
                await CloudKitSharingCoordinator.shared.pullPartnerData(into: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepyBeanDidRestoreBackup)) { note in
            if let id = note.userInfo?["babyID"] as? UUID {
                selectedBabyID = id
            } else {
                selectedBabyID = selectedBaby?.id
            }
            syncLiveActivities()
        }
    }

    private func syncLiveActivities() {
        guard let baby = selectedBaby else { return }
        Task {
            await TrackingLiveActivityManager.sync(for: baby)
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
        .modelContainer(for: [BabyProfile.self, SleepSession.self, FeedEntry.self], inMemory: true)
}
