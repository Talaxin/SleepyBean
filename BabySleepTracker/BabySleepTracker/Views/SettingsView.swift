import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var baby: BabyProfile
    let allBabies: [BabyProfile]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("settings.liveActivitiesEnabled") private var liveActivitiesEnabled = true
    @AppStorage("settings.iCloudBackupEnabled") private var iCloudBackupEnabled = true
    @State private var showAddBaby = false
    @State private var editName: String = ""
    @State private var editBirthDate: Date = Date()
    @State private var showImportRestoreConfirm = false
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var showExportPicker = false
    @State private var showImportPicker = false
    @State private var exportDocument = BackupJSONDocument()
    @State private var pendingImportData: Data?
    @State private var iCloudAccount = iCloudAccountMonitor.shared
    @State private var hasRemoteBackup = false
    @State private var versionTapCount = 0
    @State private var showClearLogsConfirm = false

    private let backupService = iCloudBackupService.shared

    private var appVersionString: String {
        AppPreferences.displayVersion
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

                ShareParentsSection(baby: baby)

                Section("iCloud") {
                    Label(iCloudAccount.statusText, systemImage: iCloudAccount.isSignedIn ? "checkmark.icloud.fill" : "icloud.slash")
                        .foregroundStyle(iCloudAccount.isSignedIn ? AppTheme.sleepPurple : .secondary)

                    if !iCloudAccount.isSignedIn {
                        Button("Sign in to iCloud") {
                            SystemSettings.openAppleAccountSettings()
                        }

                        Text("SleepyBean uses the Apple ID already on this iPhone. There is no separate in-app Apple login.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if SleepyBeanModelContainer.isCloudKitEnabled {
                        Text("Sleep and feeding data syncs automatically across your devices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        backupToiCloud()
                    } label: {
                        Label("Back up to iCloud", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(isWorking)

                    Button {
                        restoreFromiCloud()
                    } label: {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(isWorking)

                    if let lastBackupDate = backupService.lastBackupDate {
                        LabeledContent("Last backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
                    }

                    Toggle("Auto backup", isOn: $iCloudBackupEnabled)

                    Button {
                        saveAndExportBackup()
                    } label: {
                        Label("Export JSON…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import JSON…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking)
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
                    Toggle("Live activity", isOn: $liveActivitiesEnabled)
                        .onChange(of: liveActivitiesEnabled) { _, enabled in
                            handleLiveActivityToggle(enabled)
                        }

                    if liveActivitiesEnabled && !TrackingLiveActivityManager.isSupported {
                        Text("Live Activities are off for SleepyBean in iOS Settings.")
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

                Section("About") {
                    LabeledContent("App", value: "SleepyBean")
                    LabeledContent("Version", value: appVersionString)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleVersionTap()
                        }
                }

                Section {
                    Text(
                        SleepyBeanModelContainer.isCloudKitEnabled
                            ? "iCloud keeps a copy on your devices. Invite another parent from Parents above."
                            : "Back up to iCloud to keep a copy you can restore on this phone or another."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                editName = baby.name
                editBirthDate = baby.birthDate
                Task {
                    await iCloudAccount.refresh()
                    hasRemoteBackup = await backupService.hasiCloudBackup()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await iCloudAccount.refresh()
                    hasRemoteBackup = await backupService.hasiCloudBackup()
                }
            }
            .alert("Clear all logs?", isPresented: $showClearLogsConfirm) {
                Button("Clear", role: .destructive) {
                    clearAllLogs()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every sleep and feeding entry.")
            }
            .alert("Import backup?", isPresented: $showImportRestoreConfirm) {
                Button("Restore", role: .destructive) {
                    performImportRestore()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces all sleep and feeding data on this device with the imported backup file.")
            }
            .alert("Backup", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            .fileExporter(
                isPresented: $showExportPicker,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "SleepyBeanBackup.json"
            ) { result in
                switch result {
                case .success:
                    statusMessage = "JSON exported."
                case .failure(let error):
                    statusMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json]
            ) { result in
                handleImportSelection(result)
            }
            .sheet(isPresented: $showAddBaby) {
                AddBabySheet { name, birthDate in
                    let newBaby = BabyProfile(name: name, birthDate: birthDate)
                    modelContext.insert(newBaby)
                }
            }
        }
    }

    private func handleVersionTap() {
        versionTapCount += 1
        if versionTapCount >= 5 {
            versionTapCount = 0
            showClearLogsConfirm = true
            return
        }

        let taps = versionTapCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if versionTapCount == taps {
                versionTapCount = 0
            }
        }
    }

    private func clearAllLogs() {
        do {
            let sessions = try modelContext.fetch(FetchDescriptor<SleepSession>())
            for session in sessions {
                modelContext.delete(session)
            }
            let feeds = try modelContext.fetch(FetchDescriptor<FeedEntry>())
            for feed in feeds {
                modelContext.delete(feed)
            }
            try modelContext.save()
        } catch {
            for profile in allBabies {
                for session in profile.sleepSessions {
                    modelContext.delete(session)
                }
                for feed in profile.feedEntries {
                    modelContext.delete(feed)
                }
            }
            try? modelContext.save()
        }

        Task {
            await TrackingLiveActivityManager.endAll()
        }
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

    private func backupToiCloud() {
        isWorking = true
        Task {
            do {
                let summary = try backupService.summaryOfCurrentBackupData(context: modelContext)
                try await backupService.saveToiCloud(context: modelContext)
                hasRemoteBackup = true
                let stored = await backupService.summaryOfStoredBackup() ?? summary
                statusMessage = "Backup saved to iCloud (\(stored))."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func restoreFromiCloud() {
        isWorking = true
        Task {
            do {
                let babyID = try await backupService.restoreFromiCloud(context: modelContext)
                let babies = try modelContext.fetch(FetchDescriptor<BabyProfile>())
                let sessions = try modelContext.fetch(FetchDescriptor<SleepSession>())
                let feeds = try modelContext.fetch(FetchDescriptor<FeedEntry>())
                if let restored = babies.first(where: { $0.id == babyID }) ?? babies.first {
                    await TrackingLiveActivityManager.sync(for: restored)
                }
                statusMessage = "Restore complete (\(sessions.count) sleep · \(feeds.count) feeds · \(babies.count) babies)."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func saveAndExportBackup() {
        isWorking = true
        do {
            try backupService.saveBackup(context: modelContext)
            let data = try backupService.makeBackupData(context: modelContext)
            exportDocument = BackupJSONDocument(data: data)
            showExportPicker = true
        } catch {
            statusMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                statusMessage = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                pendingImportData = try Data(contentsOf: url)
                showImportRestoreConfirm = true
            } catch {
                statusMessage = error.localizedDescription
            }

        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    private func performImportRestore() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        isWorking = true
        Task {
            do {
                let babyID = try backupService.restoreBackupData(data, context: modelContext)
                let babies = try modelContext.fetch(FetchDescriptor<BabyProfile>())
                if let restored = babies.first(where: { $0.id == babyID }) ?? babies.first {
                    await TrackingLiveActivityManager.sync(for: restored)
                }
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
