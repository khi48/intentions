//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI
import Combine

/// Confirmation modal that adds friction when disabling Intentions blocking.
/// Two-halves layout: reflection (streak, stats, intention quote) above
/// action (reason input + progress-bar-in-button timer).
struct DisableBlockingConfirmationView: View {
    let streakDays: Int?
    let remainingTimeText: String
    let intentionQuote: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var reasonText: String = ""
    @State private var countdownSecondsRemaining: Double = 10.0
    @State private var isCountdownActive: Bool = false
    @State private var countdownCancellable: AnyCancellable?
    @FocusState private var isTextFieldFocused: Bool

    private let minimumCharacters = 15
    private let countdownDuration: Double = 10.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        reflectionSection
                        divider
                        actionSection
                    }
                    .padding(.horizontal)
                }
                .scrollDismissesKeyboard(.interactively)

                // Bottom button with progress bar
                progressButton
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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

    // MARK: - Reflection Section (Top Half)

    private var reflectionSection: some View {
        VStack(spacing: 0) {
            // Stats row: streak left, time stats right
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streakDays ?? 0) days")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(AppConstants.Colors.text)
                    Text("streak")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
                Spacer()
                Text(remainingTimeText)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Intention quote
            if let quote = intentionQuote, !quote.isEmpty {
                Text("\"\(quote)\"")
                    .font(.body)
                    .italic()
                    .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.85))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Action Section (Bottom Half)

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why unlock?")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppConstants.Colors.text)
                .padding(.top, 28)
                .padding(.bottom, 14)

            TextField("Write your reason...", text: $reasonText)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit { isTextFieldFocused = false }
                .onChange(of: reasonText) { _, newValue in
                    if newValue.count >= minimumCharacters && !isCountdownActive {
                        startCountdown()
                    }
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppConstants.Colors.textSecondary.opacity(0.15))
                        .frame(height: 0.5)
                }

            Text("\(reasonText.count)/\(minimumCharacters)")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.5))
                .padding(.top, 6)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Progress Bar Button

    private var progressButton: some View {
        Button(action: { onConfirm() }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppConstants.Colors.textSecondary.opacity(0.15))

                // Progress fill
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isConfirmEnabled
                              ? AppConstants.Colors.text
                              : AppConstants.Colors.textSecondary.opacity(0.08))
                        .frame(width: geometry.size.width * progressFraction)
                        .animation(.linear(duration: 1.0 / 60.0), value: progressFraction)
                }

                // Label
                Text(buttonLabel)
                    .font(.headline)
                    .foregroundColor(isConfirmEnabled
                                    ? AppConstants.Colors.background
                                    : AppConstants.Colors.textSecondary)
            }
            .frame(height: 52)
        }
        .disabled(!isConfirmEnabled)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(AppConstants.Colors.textSecondary.opacity(0.1))
            .frame(height: 0.5)
    }

    // MARK: - Computed Properties

    private var isConfirmEnabled: Bool {
        reasonText.count >= minimumCharacters && countdownSecondsRemaining <= 0
    }

    private var progressFraction: CGFloat {
        guard isCountdownActive else { return 0 }
        let elapsed = countdownDuration - countdownSecondsRemaining
        return CGFloat(max(0, min(1, elapsed / countdownDuration)))
    }

    private var buttonLabel: String {
        let seconds = Int(ceil(max(0, countdownSecondsRemaining)))
        if seconds > 0 {
            return "Disable · \(seconds)s"
        }
        return "Disable"
    }

    // MARK: - Timer

    private func startCountdown() {
        isCountdownActive = true
        countdownSecondsRemaining = countdownDuration

        countdownCancellable = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdownSecondsRemaining = max(0, countdownSecondsRemaining - (1.0 / 60.0))

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
        streakDays: 6,
        remainingTimeText: "1h 48m remaining",
        intentionQuote: "I want to be more present with my family.",
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}
