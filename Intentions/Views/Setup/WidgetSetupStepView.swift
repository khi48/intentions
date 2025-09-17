//
//  WidgetSetupStepView.swift
//  Intentions
//
//  Created by Claude on 09/09/2025.
//

import SwiftUI

/// Setup step explaining how to add and configure the Intentions widget
struct WidgetSetupStepView: View {
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Step Header
            stepHeader
            
            // Instructions
            instructionsSection
            
            // Action Button
            actionButton
            
        }
        .padding()
    }
    
    // MARK: - Step Header
    
    private var stepHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "widget.large.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            Text("Add Intentions Widget")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add the Intentions widget to your lock screen or home screen to quickly see if your apps are currently blocked or accessible.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        VStack(spacing: 20) {
            
            // Widget Benefits
            benefitsSection
            
            // How to Add Widget
            howToAddSection
            
        }
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Widget Status Indicators:")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                statusIndicator(
                    icon: "shield.fill",
                    color: .red,
                    status: "Blocked",
                    description: "Apps are currently blocked"
                )
                
                statusIndicator(
                    icon: "checkmark.circle",
                    color: .green,
                    status: "Open",
                    description: "Apps are currently accessible"
                )
                
                statusIndicator(
                    icon: "questionmark.circle",
                    color: .orange,
                    status: "Unknown",
                    description: "Status needs updating"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func statusIndicator(icon: String, color: Color, status: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var howToAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to Add Widget:")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Long press on your lock screen or home screen")
                instructionStep(number: 2, text: "Tap the \"+\" button or \"Edit\" option")
                instructionStep(number: 3, text: "Search for \"Intentions\" in the widget gallery")
                instructionStep(number: 4, text: "Select your preferred widget size and add it")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        VStack(spacing: 12) {
            Button("Complete Setup") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Text("You can add the widget later from your device settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview

#Preview {
    WidgetSetupStepView {
        print("Widget setup completed")
    }
}