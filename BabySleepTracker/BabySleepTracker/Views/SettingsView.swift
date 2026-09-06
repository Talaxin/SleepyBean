import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var showImportRestoreConfirm = false
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var showExportPicker = false
    @State private var showImportPicker = false
    @State private var exportDocument = BackupJSONDocument()
    @State private var pendingImportData: Data?

    private let backupService = iCloudBackupService.shared

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
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

                Section("iCloud Backup") {
                    Toggle("Enable backup", isOn: $iCloudBackupEnabled)

                    if iCloudBackupEnabled {
                        if let lastBackupDate = backupService.lastBackupDate {
                            LabeledContent("Last backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button {
                            saveAndExportBackup()
                        } label: {
                            Label("Save to iCloud Drive", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(isWorking)

                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Restore from backup", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(isWorking)

                        Text("Tap Save, then choose iCloud Drive in Files. SleepyBean also saves a backup automatically when you leave the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "SleepyBean")
                    LabeledContent("Version", value: appVersionString)
                }

                Section {
                    Text("Data stays on your device. Turn on backup to keep a copy in iCloud Drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                editName = baby.name
                editBirthDate = baby.birthDate
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
                defaultFilename: "SleepyBeanBackup"
            ) { result in
                switch result {
                case .success:
                    statusMessage = "Backup saved. Choose iCloud Drive to store it in the cloud."
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

    private func handleLiveActivityToggle(_ enabled: Bool) {
        Task {
            if enabled {
                await TrackingLiveActivityManager.sync(for: baby)
            } else {
                await TrackingLiveActivityManager.endAll()
            }
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
                try backupService.restoreBackupData(data, context: modelContext)
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
