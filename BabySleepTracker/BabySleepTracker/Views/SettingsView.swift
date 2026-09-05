import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var baby: BabyProfile
    let allBabies: [BabyProfile]

    @Environment(\.modelContext) private var modelContext
    @State private var showAddBaby = false
    @State private var editName: String = ""
    @State private var editBirthDate: Date = Date()

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

                    Text("Based on typical pediatric wake windows. Apps like Huckleberry refine this with your baby's patterns over time.")
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

                Section("About") {
                    LabeledContent("App", value: "SleepyBean")
                    LabeledContent("Version", value: "1.0")
                }

                Section {
                    Text("Inspired by Nara Baby's one-tap simplicity and Huckleberry's wake window guidance. All data stays on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                editName = baby.name
                editBirthDate = baby.birthDate
            }
            .sheet(isPresented: $showAddBaby) {
                AddBabySheet { name, birthDate in
                    let newBaby = BabyProfile(name: name, birthDate: birthDate)
                    modelContext.insert(newBaby)
                }
            }
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
