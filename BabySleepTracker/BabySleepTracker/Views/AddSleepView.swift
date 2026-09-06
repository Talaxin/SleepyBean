import SwiftUI
import SwiftData

struct AddSleepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let baby: BabyProfile

    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime = Date()
    @State private var sleepType: SleepType = .nap
    @State private var notes = ""
    @State private var isOngoing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep Type") {
                    Picker("Type", selection: $sleepType) {
                        ForEach(SleepType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])

                    Toggle("Still sleeping", isOn: $isOngoing)

                    if !isOngoing {
                        DatePicker("End", selection: $endTime, in: startTime...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if !isOngoing {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(SleepFormatter.formatDuration(endTime.timeIntervalSince(startTime)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let session = SleepSession(
            startTime: startTime,
            endTime: isOngoing ? nil : endTime,
            sleepType: sleepType,
            notes: notes
        )
        session.baby = baby
        modelContext.insert(session)
        try? modelContext.save()
        Task {
            if isOngoing {
                await TrackingLiveActivityManager.sync(for: baby)
            }
            await CloudKitSharingCoordinator.shared.pushPartnerData(for: baby, modelContext: modelContext)
        }
        dismiss()
    }
}

struct EditSleepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var session: SleepSession

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var sleepType: SleepType
    @State private var notes: String
    @State private var isOngoing: Bool

    init(session: SleepSession) {
        self.session = session
        _startTime = State(initialValue: session.startTime)
        _endTime = State(initialValue: session.endTime ?? Date())
        _sleepType = State(initialValue: session.type)
        _notes = State(initialValue: session.notes)
        _isOngoing = State(initialValue: session.isActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep Type") {
                    Picker("Type", selection: $sleepType) {
                        ForEach(SleepType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: [.date, .hourAndMinute])

                    Toggle("Still sleeping", isOn: $isOngoing)

                    if !isOngoing {
                        DatePicker("End", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        let baby = session.baby
                        modelContext.delete(session)
                        try? modelContext.save()
                        Task {
                            if let baby {
                                await TrackingLiveActivityManager.sync(for: baby)
                                await CloudKitSharingCoordinator.shared.pushPartnerData(for: baby, modelContext: modelContext)
                            } else {
                                await TrackingLiveActivityManager.endAll()
                            }
                        }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        session.startTime = startTime
        session.endTime = isOngoing ? nil : endTime
        session.type = sleepType
        session.notes = notes
        try? modelContext.save()
        if let baby = session.baby {
            Task {
                await TrackingLiveActivityManager.sync(for: baby)
                await CloudKitSharingCoordinator.shared.pushPartnerData(for: baby, modelContext: modelContext)
            }
        }
        dismiss()
    }
}

struct EditFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var entry: FeedEntry

    @State private var timestamp: Date
    @State private var side: FeedSide

    init(entry: FeedEntry) {
        self.entry = entry
        _timestamp = State(initialValue: entry.timestamp)
        _side = State(initialValue: entry.feedSide)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Side") {
                    Picker("Side", selection: $side) {
                        ForEach(FeedSide.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Time") {
                    DatePicker("Start", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        let baby = entry.baby
                        modelContext.delete(entry)
                        try? modelContext.save()
                        if let baby {
                            Task {
                                await CloudKitSharingCoordinator.shared.pushPartnerData(for: baby, modelContext: modelContext)
                            }
                        }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.timestamp = timestamp
                        entry.feedSide = side
                        try? modelContext.save()
                        if let baby = entry.baby {
                            Task {
                                await CloudKitSharingCoordinator.shared.pushPartnerData(for: baby, modelContext: modelContext)
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    let baby = BabyProfile(name: "Test", birthDate: Date())
    return AddSleepView(baby: baby)
}
