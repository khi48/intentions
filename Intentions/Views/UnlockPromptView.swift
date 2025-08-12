//
//  UnlockPromptView.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 5/06/25.
// UnlockPromptView.swift
// SwiftUI view for selecting an AppGroup and duration (hours/minutes) to unlock apps in the Intentions app.
// UnlockPromptView.swift
// SwiftUI view for selecting an AppGroup and duration (hours/minutes) to unlock apps in the Intentions app.

import SwiftUI

struct UnlockPromptView: View {
    // MARK: - Properties
    @EnvironmentObject private var groupManager: GroupManager
    @EnvironmentObject private var appBlocker: AppBlocker
    @State private var selectedGroup: AppGroupModel?
    @State private var selectedHours: Int = 0 // 0–2 hours
    @State private var selectedMinutes: Int = 5 // 0–55 minutes, in 5-minute increments
    @State private var errorMessage: String?
    
    // Available options for duration picker
    private let hours = [0, 1, 2]
    private let minutes = stride(from: 0, through: 55, by: 5).map { $0 }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 20) {
            Text("Unlock Apps")
                .font(.title)
                .fontWeight(.bold)
            
            // AppGroup Picker
            if let groups = try? groupManager.fetchAppGroups(), !groups.isEmpty {
                Picker("Select App Group", selection: $selectedGroup) {
                    Text("Choose a group").tag(nil as AppGroupModel?)
                    ForEach(groups) { group in
                        Text(group.name).tag(group as AppGroupModel?)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            } else {
                Text("No app groups available")
                    .foregroundColor(.gray)
                    .padding()
            }
            
            // Duration Picker (Timer App Style)
            HStack(spacing: 16) {
                // Hours Picker
                HStack(spacing: 4) {
                    Picker("", selection: $selectedHours) {
                        ForEach(hours, id: \.self) { hour in
                            Text("\(hour)")
                                .font(.title2)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 90)
                    .clipped()
                    
                    Text("hours")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                
                // Minutes Picker
                HStack(spacing: 4) {
                    Picker("", selection: $selectedMinutes) {
                        ForEach(minutes, id: \.self) { minute in
                            Text(String(format: "%02d", minute))
                                .font(.title2)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 90)
                    .clipped()
                    
                    Text("min")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
            )
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Submit Button
            Button(action: submitUnlock) {
                Text("Unlock")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidDuration ? Color.blue : Color.gray)
                    .cornerRadius(10)
            }
            .disabled(!isValidDuration)
            .padding(.horizontal)
            
            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.vertical)
        .onAppear {
            // Preselect first group if available
            if let firstGroup = try? groupManager.fetchAppGroups().first {
                selectedGroup = firstGroup
            }
        }
    }
    
    // MARK: - Computed Properties
    private var isValidDuration: Bool {
        selectedHours > 0 || selectedMinutes >= 5 // Minimum 5 minutes
    }
    
    // MARK: - Actions
    private func submitUnlock() {
        guard let selectedGroup = selectedGroup else { return }
        
        // Calculate duration as TimeInterval (seconds)
        let duration = TimeInterval((selectedHours * 3600) + (selectedMinutes * 60))
        
        do {
            try appBlocker.unlockAppGroup(selectedGroup, forDuration: duration)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to unlock: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview
struct UnlockPromptView_Previews: PreviewProvider {
    static var previews: some View {
        UnlockPromptView()
            .environmentObject(GroupManager(persistenceController: PersistenceController.testController))
            .environmentObject(AppBlocker())
//            .previewDevice("iPhone SE (3rd generation)")
            .previewInterfaceOrientation(.portrait)
        
        UnlockPromptView()
            .environmentObject(GroupManager(persistenceController: PersistenceController.testController))
            .environmentObject(AppBlocker())
            .previewDevice("iPad Pro (12.9-inch) (6th generation)")
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
