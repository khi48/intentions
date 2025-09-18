//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI

/// Confirmation modal that adds friction when disabling Intentions blocking
/// Requires user to provide intention statement and wait through 10-second delay
struct DisableBlockingConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var intentionText: String = ""
    @State private var countdownSeconds: Int = 10
    @State private var isCountdownActive: Bool = false
    @State private var countdownTimer: Timer?
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
                        countdownTimer?.invalidate()
                        countdownTimer = nil
                        onCancel()
                    }
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

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
                            .foregroundColor(intentionText.count >= minimumCharacters ? .green : .secondary)

                        Spacer()

                        if intentionText.count >= minimumCharacters {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
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
                    .stroke(Color.orange.opacity(0.2), lineWidth: 6)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: circleProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1), value: circleProgress)

                VStack(spacing: 4) {
                    Text("\(max(0, countdownSeconds))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)

                    Text("seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            Text("Please wait \(max(0, countdownSeconds)) more seconds to confirm")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(16)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            Button("Confirm Disable") {
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isConfirmEnabled)
            .tint(.orange)

            Button("Cancel") {
                countdownTimer?.invalidate()
                countdownTimer = nil
                onCancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        intentionText.count >= minimumCharacters && countdownSeconds <= 0
    }

    private var circleProgress: CGFloat {
        guard isCountdownActive else { return 0 }
        return countdownSeconds <= 0 ? 1.0 : CGFloat(10 - countdownSeconds) / 10.0
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
        countdownSeconds = 10

        // Start discrete timer for second updates
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if countdownSeconds > 0 {
                    countdownSeconds -= 1
                } else {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                }
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