//
//  WidgetSetupStepView.swift
//  Intentions
//

import SwiftUI

/// Setup step that introduces the Intent lock-screen widget. Shows a greyscale
/// preview of the two main widget states (blocked + active session), a
/// disclosure row with installation instructions, and primary/secondary CTAs.
struct WidgetSetupStepView: View {

    let onComplete: () -> Void

    @State private var isHowToShown = false

    var body: some View {
        VStack(spacing: 24) {
            header

            LockScreenPreviewCard()

            howToRow

            ctaStack

            Spacer(minLength: 40)
        }
        .sheet(isPresented: $isHowToShown) {
            HowToAddWidgetSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppConstants.Colors.surface)
                    .frame(width: 80, height: 80)

                Image(systemName: "widget.large.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(AppConstants.Colors.text)
            }

            Text("Add the Intent widget")
                .font(.title2)
                .fontWeight(.semibold)

            Text("A quick glance at the lock screen tells you whether you're protected — or in an active session.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }

    // MARK: - How-to row

    private var howToRow: some View {
        Button {
            isHowToShown = true
        } label: {
            HStack(spacing: 8) {
                Text("How to add it to your lock screen")
                    .foregroundColor(AppConstants.Colors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppConstants.Colors.surface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTAs

    private var ctaStack: some View {
        VStack(spacing: 6) {
            SettingsPrimaryButton("I added it", systemImage: "arrow.right") {
                onComplete()
            }

            Button("Skip for now") {
                onComplete()
            }
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.textSecondary)
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Lock screen preview card

private struct LockScreenPreviewCard: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color.white.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.3, y: 0.2),
                    startRadius: 0,
                    endRadius: 220
                )
            )

            HStack(spacing: 14) {
                CircularBlockedPill()
                RectangularActiveSessionPill()
            }
            .padding(.vertical, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(AppConstants.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Widget pills (preview-only renderings)

private struct CircularBlockedPill: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
            Text("BLOCKED")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 78, height: 78)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.5))
        )
    }
}

private struct RectangularActiveSessionPill: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Deep Work")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("45m remaining")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.72))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: geo.size.width * 0.62)
                    }
                }
                .frame(height: 3)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(width: 168, height: 78, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - How-to sheet

private struct HowToAddWidgetSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        header

                        instructionGroup(
                            icon: "lock.fill",
                            title: "On your lock screen",
                            steps: [
                                "Press and hold anywhere on your lock screen.",
                                "Tap Customise, then tap the lock screen.",
                                "Tap the widgets row below the clock and choose Intent."
                            ]
                        )

                        instructionGroup(
                            icon: "iphone",
                            title: "On your home screen",
                            steps: [
                                "Press and hold an empty area on your home screen.",
                                "Tap the + button in the top-left corner.",
                                "Search for Intent and add the widget."
                            ]
                        )

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppConstants.Colors.text)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppConstants.Colors.surface)
                    .frame(width: 64, height: 64)

                Image(systemName: "widget.large.badge.plus")
                    .font(.system(size: 30))
                    .foregroundColor(AppConstants.Colors.text)
            }

            Text("Adding the widget")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppConstants.Colors.text)

            Text("Two ways to add Intent — pick whichever fits your setup.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func instructionGroup(icon: String, title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppConstants.Colors.text)
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(AppConstants.Colors.text)
                }
                Rectangle()
                    .fill(AppConstants.Colors.textSecondary.opacity(0.25))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AppConstants.Colors.surface)
                                .frame(width: 30, height: 30)
                            Text("\(idx + 1)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppConstants.Colors.text)
                        }

                        Text(step)
                            .font(.body)
                            .foregroundColor(AppConstants.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppConstants.Colors.background.ignoresSafeArea()
        ScrollView {
            WidgetSetupStepView(onComplete: {})
                .padding()
        }
    }
}
