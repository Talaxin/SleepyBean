import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var baby: BabyProfile
    let allBabies: [BabyProfile]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("settings.liveActivitiesEnabled") private var liveActivitiesEnabled = true
    @AppStorage("settings.iCloudBackupEnabled") private var iCloudBackupEnabled = false
    @State private var showAddBaby = false
    @State private var editName: String = ""
    @State private var editBirthDate: Date = Date()
    @State private var showRestoreConfirm = false
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var iCloudSignedIn = iCloudBackupService.shared.isSignedInToiCloud

    private let backupService = iCloudBackupService.shared

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var systemLiveActivitiesEnabled: Bool {
        TrackingLiveActivityManager.isSupported
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby Profile") {
                    TextField("Name", text: $editName)
                        .onChange(of: editName) { _, newValue in
                            baby.name = newValue
                        }

                    DatePicker("Birth date", selection: $editBirthDate, in: ...Date(), displayedComponents: .date)
                        .onChange(of: editBirthDate) { _, newValue in
                            baby.birthDate = newValue
                        }

                    LabeledContent("Age", value: baby.ageDescription)
                }

                Section("Wake Windows") {
                    let guidance = WakeWindowCalculator.guidance(forAgeInMonths: baby.ageInMonths)
                    LabeledContent("Current window", value: guidance.rangeDescription)
                    LabeledContent("Age bracket", value: guidance.label)

                    Text("Wake windows use age-appropriate ranges to help you spot nap timing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if allBabies.count > 1 {
                    Section("All Babies") {
                        ForEach(allBabies, id: \.id) { profile in
                            HStack {
                                Text(profile.name)
                                Spacer()
                                if profile.id == baby.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.sleepPurple)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Add Another Baby") {
                        showAddBaby = true
                    }
                }

                Section("Live Activity") {
                    Toggle("Show lock screen timer", isOn: $liveActivitiesEnabled)
                        .onChange(of: liveActivitiesEnabled) { _, enabled in
                            handleLiveActivityToggle(enabled)
                        }

                    LabeledContent("iOS permission") {
                        Text(systemLiveActivitiesEnabled ? "Allowed" : "Off in iOS Settings")
                            .foregroundStyle(systemLiveActivitiesEnabled ? .green : .orange)
                    }

                    if liveActivitiesEnabled && !systemLiveActivitiesEnabled {
                        Text("Turn on Live Activities for SleepyBean in iOS Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Open iOS Settings") {
                            SystemSettings.openAppSettings()
                        }
                    } else {
                        Text("Shows a live nap/sleep timer on your lock screen and Dynamic Island.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("iCloud Backup") {
                    Toggle("Enable iCloud backup", isOn: $iCloudBackupEnabled)

                    LabeledContent("iCloud account") {
                        Text(iCloudSignedIn ? "Signed in" : "Not signed in")
                            .foregroundStyle(iCloudSignedIn ? .green : .orange)
                    }

                    if iCloudBackupEnabled && !iCloudSignedIn {
                        Text("Sign in to iCloud and turn on iCloud Drive to back up your data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Sign in to iCloud") {
                            SystemSettings.openiCloudSettings()
                        }

                        Button("Open SleepyBean in Settings") {
                            SystemSettings.openAppSettings()
                        }
                    }

                    if iCloudBackupEnabled && iCloudSignedIn {
                        if let lastBackupDate = backupService.lastBackupDate {
                            LabeledContent("Last backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button {
                            performBackup()
                        } label: {
                            Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(isWorking)

                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(isWorking)

                        Text("SleepyBean also backs up automatically when you leave the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "SleepyBean")
                    LabeledContent("Version", value: appVersionString)
                }

                Section {
                    Text("Data stays on your device unless you turn on iCloud backup above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                editName = baby.name
                editBirthDate = baby.birthDate
                refreshiCloudStatus()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshiCloudStatus()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
                refreshiCloudStatus()
            }
            .alert("Restore from iCloud?", isPresented: $showRestoreConfirm) {
                Button("Restore", role: .destructive) {
                    performRestore()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces all sleep and feeding data on this device with your latest iCloud backup.")
            }
            .alert("iCloud", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                if statusMessage?.contains("Sign in") == true || statusMessage?.contains("not available") == true {
                    Button("Open iCloud Settings") {
                        SystemSettings.openiCloudSettings()
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            .sheet(isPresented: $showAddBaby) {
                AddBabySheet { name, birthDate in
                    let newBaby = BabyProfile(name: name, birthDate: birthDate)
                    modelContext.insert(newBaby)
                }
            }
        }
    }

    private func refreshiCloudStatus() {
        iCloudSignedIn = backupService.isSignedInToiCloud
    }

    private func handleLiveActivityToggle(_ enabled: Bool) {
        Task {
            if enabled {
                await TrackingLiveActivityManager.sync(for: baby)
            } else {
                await TrackingLiveActivityManager.endAll()
            }
        }
    }

    private func performBackup() {
        guard iCloudBackupEnabled else {
            statusMessage = "Turn on iCloud backup in Settings first."
            return
        }

        guard iCloudSignedIn else {
            statusMessage = "Sign in to iCloud in Settings, then try again."
            return
        }

        isWorking = true
        Task {
            do {
                try await backupService.backup(context: modelContext)
                statusMessage = "Backup saved to iCloud."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func performRestore() {
        guard iCloudBackupEnabled else {
            statusMessage = "Turn on iCloud backup in Settings first."
            return
        }

        guard iCloudSignedIn else {
            statusMessage = "Sign in to iCloud in Settings, then try again."
            return
        }

        isWorking = true
        Task {
            do {
                try await backupService.restore(context: modelContext)
                await TrackingLiveActivityManager.sync(for: baby)
                statusMessage = "Restore complete."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

struct AddBabySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthDate = Date()
    let onSave: (String, Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                DatePicker("Birth date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
            }
            .navigationTitle("Add Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.isEmpty ? "Baby" : name, birthDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SettingsView(
        baby: BabyProfile(name: "Luna", birthDate: Date()),
        allBabies: []
    )
}
