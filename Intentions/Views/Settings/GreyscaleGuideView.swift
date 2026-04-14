//
//  GreyscaleGuideView.swift
//  Intentions
//

import SwiftUI

/// Guide view showing how to enable greyscale in iOS Settings
struct GreyscaleGuideView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 48))
                        .foregroundColor(AppConstants.Colors.accent)

                    Text("Greyscale makes your phone less appealing, reducing the urge to scroll.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    stepRow(number: 1, text: "Open **Settings**")
                    stepRow(number: 2, text: "Go to **Accessibility**")
                    stepRow(number: 3, text: "Tap **Display & Text Size**")
                    stepRow(number: 4, text: "Tap **Colour Filters**")
                    stepRow(number: 5, text: "Turn on **Colour Filters** and select **Greyscale**")
                }
                .padding()
                .background(AppConstants.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
                )

                SettingsPrimaryButton("Open iOS Settings", systemImage: "gear") {
                    openSettings()
                }

                Spacer()
            }
            .padding()
        }
        .settingsPageBackground()
        .navigationTitle("Enable Greyscale")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppConstants.Colors.background)
                .frame(width: 22, height: 22)
                .background(AppConstants.Colors.accent)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)

            Spacer()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
