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
    @State private var showRestoreConfirm = false
    @State private var showImportRestoreConfirm = false
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var iCloudStatus = iCloudBackupService.shared.accountStatus
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

                    LabeledContent("iCloud status") {
                        Text(iCloudStatus.label)
                            .foregroundStyle(iCloudStatus.isPositive ? .green : .orange)
                    }

                    if iCloudBackupEnabled {
                        switch iCloudStatus {
                        case .notSignedIn:
                            Text("Sign in to iCloud and turn on iCloud Drive.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Sign in to iCloud") {
                                SystemSettings.openiCloudSettings()
                            }

                        case .signedInNoContainer:
                            Text("You are signed in, but this install cannot access iCloud Drive. Use Export to Files below and choose iCloud Drive, or re-sign in Feather with iCloud enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Open iCloud Settings") {
                                SystemSettings.openiCloudSettings()
                            }

                        case .ready:
                            if let lastBackupDate = backupService.lastBackupDate {
                                LabeledContent("Last iCloud backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
                            }

                            Button {
                                performCloudBackup()
                            } label: {
                                Label("Back Up to iCloud", systemImage: "icloud.and.arrow.up")
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
                }

                Section("Files Backup") {
                    if let lastLocalBackupDate = backupService.lastLocalBackupDate {
                        LabeledContent("Last local backup", value: lastLocalBackupDate.formatted(date: .abbreviated, time: .shortened))
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label("Export to Files", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import from Files", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking)

                    Text("Save a backup to iCloud Drive, On My iPhone, or another device. Works even when automatic iCloud backup is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "SleepyBean")
                    LabeledContent("Version", value: appVersionString)
                }

                Section {
                    Text("Data stays on your device. Turn on iCloud backup or export to Files to keep a copy elsewhere.")
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
                    performCloudRestore()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces all sleep and feeding data on this device with your latest iCloud backup.")
            }
            .alert("Import backup?", isPresented: $showImportRestoreConfirm) {
                Button("Import", role: .destructive) {
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
                if shouldOfferiCloudSettings {
                    Button("Open iCloud Settings") {
                        SystemSettings.openiCloudSettings()
                    }
                }
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
                if case .success = result {
                    statusMessage = "Backup exported. You can save it to iCloud Drive in Files."
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

    private var shouldOfferiCloudSettings: Bool {
        guard let statusMessage else { return false }
        return statusMessage.localizedCaseInsensitiveContains("icloud")
    }

    private func refreshiCloudStatus() {
        iCloudStatus = backupService.accountStatus
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

    private func prepareExport() {
        isWorking = true
        do {
            let data = try backupService.makeBackupData(context: modelContext)
            exportDocument = BackupJSONDocument(data: data)
            try backupService.saveLocalBackup(context: modelContext)
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
        guard let pendingImportData else { return }
        isWorking = true
        Task {
            do {
                try backupService.restoreBackupData(pendingImportData, context: modelContext)
                await TrackingLiveActivityManager.sync(for: baby)
                statusMessage = "Import complete."
            } catch {
                statusMessage = error.localizedDescription
            }
            pendingImportData = nil
            isWorking = false
        }
    }

    private func performCloudBackup() {
        guard iCloudBackupEnabled else {
            statusMessage = "Turn on iCloud backup first."
            return
        }

        isWorking = true
        Task {
            do {
                try await backupService.backup(context: modelContext)
                refreshiCloudStatus()
                statusMessage = "Backup saved to iCloud."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func performCloudRestore() {
        guard iCloudBackupEnabled else {
            statusMessage = "Turn on iCloud backup first."
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
