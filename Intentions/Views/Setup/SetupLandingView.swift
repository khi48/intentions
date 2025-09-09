//
//  SetupLandingView.swift
//  Intentions
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI

/// Initial setup landing page that introduces users to the setup process
/// Shows overview of setup steps and provides a clear starting point
struct SetupLandingView: View {
    
    let onGetStarted: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            
            // Header Section
            headerSection
            
            // Setup Overview
            setupOverviewSection
            
            // Get Started Button
            getStartedButton
            
            Spacer(minLength: 50)
        }
        .padding()
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "gear.badge.checkmark")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Welcome to Intentions")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Let's set up your app for mindful phone usage. This quick setup will help you take control of your digital habits.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    // MARK: - Setup Overview
    
    private var setupOverviewSection: some View {
        VStack(spacing: 20) {
            Text("What we'll set up:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                setupStep(
                    icon: "hourglass.circle.fill",
                    title: "Screen Time Permissions",
                    description: "Grant access to manage app blocking during focused sessions",
                    stepNumber: 1
                )
                
                setupStep(
                    icon: "square.grid.3x3.topleft.filled",
                    title: "App Category Mapping", 
                    description: "Configure which apps belong to which categories for intelligent blocking",
                    stepNumber: 2
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func setupStep(icon: String, title: String, description: String, stepNumber: Int) -> some View {
        HStack(spacing: 16) {
            // Step number circle
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("\(stepNumber)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Get Started Button
    
    private var getStartedButton: some View {
        VStack(spacing: 16) {
            Button("Get Started") {
                onGetStarted()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.headline)
            
            Text("This setup takes about 2 minutes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SetupLandingView {
        print("Get started tapped")
    }
}