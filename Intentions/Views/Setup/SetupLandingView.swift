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
        VStack(spacing: 24) {

            // Header Section
            headerSection
                .padding(.top, 60)

            // Setup Overview
            setupOverviewSection

            // Get Started Button
            getStartedButton

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Text("Welcome to Intent")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Let's set up your app for mindful phone usage. This quick setup will help you take control of your digital habits.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }
    
    // MARK: - Setup Overview
    
    private var setupOverviewSection: some View {
        VStack(spacing: 16) {
            Text("What we'll set up:")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
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

                setupStep(
                    icon: "widget.large.badge.plus",
                    title: "Widget Setup",
                    description: "Add the Intent widget to see your blocking status at a glance",
                    stepNumber: 3
                )
            }
        }
        .padding(18)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
    
    private func setupStep(icon: String, title: String, description: String, stepNumber: Int) -> some View {
        HStack(spacing: 16) {
            // Step number circle
            ZStack {
                Circle()
                    .fill(AppConstants.Colors.surface)
                    .frame(width: 32, height: 32)

                Text("\(stepNumber)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.text)
            }

            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.text)
                .frame(width: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }
    
    // MARK: - Get Started Button
    
    private var getStartedButton: some View {
        VStack(spacing: 12) {
            Button("Get Started") {
                onGetStarted()
            }
            .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
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
    }
}