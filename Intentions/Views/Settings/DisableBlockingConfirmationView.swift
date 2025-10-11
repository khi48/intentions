//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI
import Combine

/// Confirmation modal that adds friction when disabling Intentions blocking
/// Requires user to provide intention statement and wait through 10-second delay
struct DisableBlockingConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var intentionText: String = ""
    @State private var countdownSecondsRemaining: Double = 10.0
    @State private var isCountdownActive: Bool = false
    @State private var countdownCancellable: AnyCancellable?
    @FocusState private var isTextFieldFocused: Bool

    private let minimumCharacters = 15

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    // Header Section - More compact
                    headerSection

                    // Intention Input Section
                    intentionInputSection

                    // Countdown Section - Give it breathing room
                    if isCountdownActive {
                        countdownSection
                            .padding(.vertical, 20)
                    }

                    // Spacer to push buttons down
                    Spacer(minLength: isCountdownActive ? 20 : 60)

                    // Action Buttons Section
                    actionButtonsSection
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.8)
            }
            .navigationTitle("Confirm Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        countdownCancellable?.cancel()
                        countdownCancellable = nil
                        onCancel()
                    }
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onDisappear {
            countdownCancellable?.cancel()
            countdownCancellable = nil
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(AppConstants.Colors.textSecondary)

            Text("Disable App Blocking?")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Please help us understand why you want to disable blocking.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intentionInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                    Text("Why do you need to disable blocking?")
                        .font(.headline)

                    TextField("Share your intention here...", text: $intentionText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isTextFieldFocused = false
                        }
                        .onChange(of: intentionText) { oldValue, newValue in
                            if newValue.count >= minimumCharacters && !isCountdownActive {
                                startCountdown()
                            }
                        }

                    HStack {
                        Text("\(intentionText.count)/\(minimumCharacters) characters minimum")
                            .font(.caption)
                            .foregroundColor(intentionText.count >= minimumCharacters ? AppConstants.Colors.text : .secondary)

                        Spacer()

                        if intentionText.count >= minimumCharacters {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppConstants.Colors.text)
                        }
                    }

        }
    }

    private var countdownSection: some View {
        VStack(spacing: 20) {
            Text("Please take a moment to reflect...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .stroke(AppConstants.Colors.textSecondary.opacity(0.3), lineWidth: 6)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: circleProgress)
                    .stroke(AppConstants.Colors.textSecondary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("\(Int(ceil(max(0, countdownSecondsRemaining))))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(AppConstants.Colors.textSecondary)

                    Text("seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)

        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(AppConstants.Colors.surface)
        .cornerRadius(16)
    }

    private var actionButtonsSection: some View {
        Button("Confirm Disable") {
            onConfirm()
        }
        .buttonStyle(.bordered)
        .foregroundColor(isConfirmEnabled ? AppConstants.Colors.text : AppConstants.Colors.textSecondary)
        .controlSize(.large)
        .disabled(!isConfirmEnabled)
        .tint(isConfirmEnabled ? AppConstants.Colors.text : AppConstants.Colors.textSecondary)
        .opacity(isConfirmEnabled ? 1.0 : 0.5)
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        intentionText.count >= minimumCharacters && countdownSecondsRemaining <= 0
    }

    private var circleProgress: CGFloat {
        guard isCountdownActive else { return 0 }
        let progress = (10.0 - countdownSecondsRemaining) / 10.0
        return CGFloat(max(0, min(1, progress)))
    }

    private var isIntentionValid: Bool {
        let trimmed = intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return false }

        // Basic validation to prevent lazy responses
        let lowercased = trimmed.lowercased()
        let invalidResponses = ["asdf", "test", "because", "idk", "whatever", "abc", "123"]

        for invalid in invalidResponses {
            if lowercased.contains(invalid) && trimmed.count < 25 {
                return false
            }
        }

        return true
    }

    // MARK: - Private Methods

    private func startCountdown() {
        guard isIntentionValid else { return }

        isCountdownActive = true
        countdownSecondsRemaining = 10.0

        // Use Timer.publish for ultra-smooth countdown at 60fps
        countdownCancellable = Timer.publish(every: 1.0/60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdownSecondsRemaining = max(0, countdownSecondsRemaining - (1.0/60.0))

                // Stop when countdown reaches zero
                if countdownSecondsRemaining <= 0 {
                    countdownCancellable?.cancel()
                    countdownCancellable = nil
                }
            }
    }
}

// MARK: - Preview

#Preview {
    DisableBlockingConfirmationView(
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}