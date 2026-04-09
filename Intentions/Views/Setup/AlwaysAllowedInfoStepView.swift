//
//  AlwaysAllowedInfoStepView.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import SwiftUI

/// Setup step explaining Screen Time's "Always Allowed" feature
/// This allows users to configure essential apps that bypass Intent's blocking
struct AlwaysAllowedInfoStepView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header icon and title
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 64))
                        .foregroundColor(AppConstants.Colors.text)

                    Text("Essential Apps")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(AppConstants.Colors.text)

                    Text("Configure apps that you always need access to")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                // Information card
                VStack(alignment: .leading, spacing: 20) {
                    // What is Always Allowed
                    infoSection(
                        icon: "info.circle.fill",
                        title: "What is Always Allowed?",
                        description: "iOS Screen Time has a built-in feature that lets you mark certain apps as \"Always Allowed.\" These apps will remain accessible even when Intent blocks other apps."
                    )

                    Divider()

                    // When to use it
                    infoSection(
                        icon: "exclamationmark.triangle.fill",
                        title: "Use This Carefully",
                        description: "Only mark apps as Always Allowed if you truly need them for critical tasks (like work communication, health apps, or navigation). Adding too many apps defeats the purpose of mindful phone usage."
                    )

                    Divider()

                    // How to configure
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "gear.badge.checkmark")
                                .font(.title2)
                                .foregroundColor(AppConstants.Colors.text)
                                .frame(width: 32)

                            Text("How to Configure")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.text)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            pathStep(number: 1, text: "Open Settings app")
                            pathStep(number: 2, text: "Tap Screen Time")
                            pathStep(number: 3, text: "Tap Always Allowed")
                            pathStep(number: 4, text: "Add your essential apps")
                        }
                        .padding(.leading, 44)
                    }

                    Divider()

                    // Examples
                    infoSection(
                        icon: "lightbulb.fill",
                        title: "Good Examples",
                        description: "Phone, Messages, Calendar, Maps, Banking apps, Health apps, Work communication tools"
                    )

                    infoSection(
                        icon: "xmark.circle.fill",
                        title: "Avoid Adding",
                        description: "Social media, games, entertainment apps, shopping apps, or any app you're trying to use more mindfully"
                    )
                }
                .padding(20)
                .background(AppConstants.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Note
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppConstants.Colors.text)

                        Text("You can configure Always Allowed apps now or later. Intent will work perfectly either way.")
                            .font(.footnote)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(AppConstants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Continue button
                Button(action: onContinue) {
                    HStack {
                        Text("Continue")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppConstants.Colors.buttonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
        .background(AppConstants.Colors.background)
    }

    // MARK: - Helper Views

    private func infoSection(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.text)
                    .frame(width: 32)

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.text)
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 44)
        }
    }

    private func pathStep(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppConstants.Colors.text)
                .frame(width: 24, alignment: .leading)

            Text(text)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.text)
        }
    }
}

#Preview {
    AlwaysAllowedInfoStepView(onContinue: {})
}
