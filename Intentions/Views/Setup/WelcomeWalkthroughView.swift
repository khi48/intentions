//
//  WelcomeWalkthroughView.swift
//  Intentions
//
//  Created by Claude on 23/05/2026.
//

import SwiftUI

/// Single welcome card shown on fresh install before the Screen Time auth prompt.
/// Primes the user on the inverted blocking model (all apps blocked by default)
/// before permission is asked.
struct WelcomeWalkthroughView: View {

    let onContinue: () -> Void

    private static let bodyCopy = "Intent keeps every app on your phone blocked by default. To use an app, intentionally unblock it for only as long as you need. When the time's up, it locks itself again."

    var body: some View {
        SetupStepScaffold(progressStep: nil) {
            VStack(spacing: 32) {
                Spacer(minLength: 12)

                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: 16) {
                    title
                    body(text: Self.bodyCopy)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Welcome to Intent. \(Self.bodyCopy)")
            }
        } footer: {
            VStack(spacing: 10) {
                stamp
                SettingsPrimaryButton("Continue", systemImage: "arrow.right") {
                    onContinue()
                }
                .accessibilityHint("Begins setup")
            }
        }
    }

    // MARK: - Text blocks

    private var title: some View {
        (
            Text("Welcome to ")
                .font(.system(.largeTitle, design: .serif).weight(.regular))
                .foregroundColor(AppConstants.Colors.text)
            +
            Text("Intent.")
                .font(.system(.largeTitle, design: .serif).weight(.regular).italic())
                .foregroundColor(AppConstants.Colors.text)
        )
        .multilineTextAlignment(.center)
    }

    private func body(text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundColor(AppConstants.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stamp: some View {
        Text("Setup takes about 2 minutes")
            .font(.caption)
            .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.6))
    }
}

// MARK: - Preview

#Preview {
    WelcomeWalkthroughView(onContinue: {})
}
