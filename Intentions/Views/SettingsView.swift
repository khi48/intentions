//
//  SettingsView.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 5/06/25.
//
import SwiftUI
import FamilyControls

struct SettingsView: View {
    // MARK: - Properties
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var scheduleManager: ScheduleManager
    @State private var appGroups: [AppGroupModel] = []
    @State private var schedule: UsageScheduleModel?
    @State private var newGroupName: String = ""
    @State private var selectedApps: FamilyActivitySelection = FamilyActivitySelection()
    @State private var isShowingPicker: Bool = false
    @State private var errorMessage: String?
    @State private var isRequestingAuthorization: Bool = false

    
    // MARK: - Body
    var body: some View {
        NavigationView {
            List {
                // App Groups Section
                Section(header: Text("App Groups")) {
                    // Add New Group
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Group Name", text: $newGroupName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: {
                            requestAuthorization {
                                isShowingPicker = true
                            }
                        }) {
                            Text("Select Apps")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        if !selectedApps.applicationTokens.isEmpty {
                            Text("Selected: \(selectedApps.applications.compactMap { $0.localizedDisplayName }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Button(action: addGroup) {
                            Text("Add Group")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .disabled(newGroupName.isEmpty || selectedApps.applicationTokens.isEmpty)
                    }
                    .padding(.vertical, 4)
                    List {
                        // Existing Groups
                        ForEach(appGroups) { group in
                            NavigationLink(
                                destination: AppGroupDetailView(group: group)
                                    .environmentObject(groupManager)
                            ) {
                                VStack(alignment: .leading) {
                                    Text(group.name)
                                        .font(.headline)
                                    Text(group.bundleIDs.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete(perform: deleteGroups)
                    }

                }
                
                // Usage Schedule Section
                Section(header: Text("Usage Schedule")) {
                    if let schedule = schedule {
                        DatePicker(
                            "Start Time",
                            selection: Binding(
                                get: { schedule.startTime },
                                set: { newValue in updateSchedule(startTime: newValue) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        
                        DatePicker(
                            "End Time",
                            selection: Binding(
                                get: { schedule.endTime },
                                set: { newValue in updateSchedule(endTime: newValue) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                    } else {
                        Text("No schedule set")
                            .foregroundColor(.gray)
                        Button("Create Schedule") {
                            createDefaultSchedule()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                EditButton()
            }
            .familyActivityPicker(isPresented: $isShowingPicker, selection: $selectedApps)
            .onAppear {
                loadData()
            }
//            .alert(isPresented: Binding<Bool>(
//                get: { errorMessage != nil },
//                set: { if !$0 { errorMessage = nil } }
//            )) {
//                Alert(title: Text("Error"), message: Text(errorMessage ?? ""), dismissButton: .default(Text("OK")))
//            }
            // Replace the complex alert binding with this:
//            .alert("Error", isPresented: $showingError) {
//                Button("OK") { }
//            } message: {
//                Text(errorMessage ?? "")
//            }
//            .onChange(of: errorMessage) { _, newValue in
//                showingError = newValue != nil
//            }
            .disabled(isRequestingAuthorization)
        }
    }
    
    // MARK: - Actions
    private func loadData() {
        print("Loading data")
        do {
            print(appGroups)
            appGroups = try groupManager.fetchAppGroups()
            print(appGroups)
            let schedules = try scheduleManager.fetchSchedules()
            schedule = schedules.first // Use first active schedule
            print("loaded appgroups and schedule")
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
    
    private func addGroup() {
        do {
            print("add group?")
            let bundleIDs = selectedApps.applications.compactMap { $0.bundleIdentifier }
            guard !bundleIDs.isEmpty else {
                throw NSError(domain: "SettingsView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid bundle IDs selected"])
            }
            _ = try groupManager.createAppGroup(name: newGroupName, bundleIDs: bundleIDs)
            appGroups = try groupManager.fetchAppGroups()
            newGroupName = ""
            selectedApps = FamilyActivitySelection()
        } catch {
            errorMessage = "Failed to add group: \(error.localizedDescription)"
        }
    }
    
    private func deleteGroups(at offsets: IndexSet) {
        do {
            print("delete groups")
            for index in offsets {
                print(index)
                print(appGroups)
                try groupManager.deleteAppGroup(id: appGroups[index].id)
            }
            appGroups = try groupManager.fetchAppGroups()
        } catch {
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
        }
    }
    
    private func createDefaultSchedule() {
        do {
            let now = Date()
            let defaultEndTime = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
            let newSchedule = try scheduleManager.setSchedule(
                id: nil,
                isActive: true,
                startTime: now,
                endTime: defaultEndTime
            )
            schedule = newSchedule
        } catch {
            errorMessage = "Failed to create schedule: \(error.localizedDescription)"
        }
    }
    
    private func updateSchedule(startTime: Date? = nil, endTime: Date? = nil) {
        guard let schedule = schedule else { return }
        do {
            let _ = try scheduleManager.setSchedule(
                id: schedule.id,
                isActive: schedule.isActive,
                startTime: startTime ?? schedule.startTime,
                endTime: endTime ?? schedule.endTime
            )
            self.schedule = UsageScheduleModel(
                id: schedule.id,
                isActive: schedule.isActive,
                startTime: startTime ?? schedule.startTime,
                endTime: endTime ?? schedule.endTime
            )
        } catch {
            errorMessage = "Failed to update schedule: \(error.localizedDescription)"
        }
    }
    
    private func requestAuthorization(completion: @escaping () -> Void) {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    isRequestingAuthorization = false
                    completion()
                }
            } catch {
                await MainActor.run {
                    isRequestingAuthorization = false
                    errorMessage = "Screen Time authorization failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - AppGroup Detail View
struct AppGroupDetailView: View {
    @EnvironmentObject private var groupManager: GroupManager
    let group: AppGroupModel
    @State private var name: String
    @State private var selectedApps: FamilyActivitySelection
    @State private var errorMessage: String?
    @State private var isShowingPicker: Bool = false
    @State private var isRequestingAuthorization: Bool = false
    
    init(group: AppGroupModel) {
        self.group = group
        _name = State(initialValue: group.name)
        _selectedApps = State(initialValue: FamilyActivitySelection())
    }
    
    var body: some View {
        Form {
            Section(header: Text("Group Details")) {
                TextField("Name", text: $name)
                Button(action: {
                    requestAuthorization {
                        isShowingPicker = true
                    }
                }) {
                    Text("Select Apps")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                if !selectedApps.applicationTokens.isEmpty {
                    Text("Selected: \(selectedApps.applications.compactMap { $0.localizedDisplayName }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text("Current: \(group.bundleIDs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Button("Save Changes") {
                saveChanges()
            }
            .disabled(name.isEmpty || (selectedApps.applicationTokens.isEmpty && group.bundleIDs.isEmpty))
        }
        .navigationTitle("Edit Group")
        .familyActivityPicker(isPresented: $isShowingPicker, selection: $selectedApps)
        .alert(isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Alert(title: Text("Error"), message: Text(errorMessage ?? ""), dismissButton: .default(Text("OK")))
        }
        .disabled(isRequestingAuthorization)
    }
    
    private func saveChanges() {
        do {
            let bundleIDs = selectedApps.applicationTokens.isEmpty
                ? group.bundleIDs
                : selectedApps.applications.compactMap { $0.bundleIdentifier }
            let _ = try groupManager.updateAppGroup(id: group.id, name: name, bundleIDs: bundleIDs)
        } catch {
            errorMessage = "Failed to update group: \(error.localizedDescription)"
        }
    }
    
    private func requestAuthorization(completion: @escaping () -> Void) {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    isRequestingAuthorization = false
                    completion()
                }
            } catch {
                await MainActor.run {
                    isRequestingAuthorization = false
                    errorMessage = "Screen Time authorization failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(GroupManager(persistenceController: PersistenceController.testController))
            .environmentObject(ScheduleManager(persistenceController: PersistenceController.testController))
            .previewDevice("iPhone 14")
            .previewInterfaceOrientation(.portrait)
        
        SettingsView()
            .environmentObject(GroupManager(persistenceController: PersistenceController.testController))
            .environmentObject(ScheduleManager(persistenceController: PersistenceController.testController))
            .previewDevice("iPad Pro (12.9-inch) (6th generation)")
            .previewInterfaceOrientation(.landscapeLeft)
    }
}

