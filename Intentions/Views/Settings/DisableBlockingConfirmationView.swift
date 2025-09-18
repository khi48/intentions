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
    @State private var countdownTask: Task<Void, Never>?

    private let minimumCharacters = 15

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)

                    Text("Disable App Blocking?")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("We understand you need flexibility. Please help us understand why you want to disable blocking.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Intention Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why do you need to disable blocking?")
                        .font(.headline)

                    TextField("Share your intention here...", text: $intentionText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
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

                // Countdown Section
                if isCountdownActive {
                    VStack(spacing: 16) {
                        Text("Please take a moment to reflect...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ZStack {
                            Circle()
                                .stroke(Color.orange.opacity(0.3), lineWidth: 8)
                                .frame(width: 100, height: 100)

                            Circle()
                                .trim(from: 0, to: CGFloat(10 - countdownSeconds) / 10)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: countdownSeconds)

                            Text("\(countdownSeconds)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }

                        Text("Confirm will be available in \(countdownSeconds) seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button("Confirm Disable") {
                        countdownTask?.cancel()
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isConfirmEnabled)
                    .tint(.orange)

                    Button("Cancel") {
                        countdownTask?.cancel()
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.bottom)
            }
            .padding()
            .navigationTitle("Confirm Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        countdownTask?.cancel()
                        onCancel()
                    }
                }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        intentionText.count >= minimumCharacters && countdownSeconds == 0
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

        countdownTask = Task {
            for i in (0..<10).reversed() {
                if Task.isCancelled { return }
                await MainActor.run {
                    countdownSeconds = i
                }
                if i > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
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