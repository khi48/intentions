//
//  DisableBlockingConfirmationView.swift
//  Intentions
//
//  Created by Claude on 18/09/2025.
//

import SwiftUI

/// Confirmation modal that adds friction when disabling Intentions blocking.
/// Layout: stat boxes at the top (streak + optional time remaining), intention quote
/// in the middle, reason field, and a progress-bar Disable button at the bottom.
struct DisableBlockingConfirmationView: View {
    let streakDays: Int?
    /// Time until the next free-time window. Nil when the user is currently in free time —
    /// in which case the second stat box shows a "Free Time" status instead.
    let timeUntilFreeTimeText: String?
    let intentionQuote: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var reasonText: String = ""
    @State private var countdownEndDate: Date?
    @State private var isCountdownComplete: Bool = false
    @State private var animatedProgress: CGFloat = 0
    @State private var countdownTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool

    private let countdownDuration: Double = 10.0

    /// Whether the user must type their intention quote exactly to confirm
    private var requiresQuoteMatch: Bool {
        intentionQuote != nil && !intentionQuote!.isEmpty
    }

    private var textMatchesQuote: Bool {
        guard let quote = intentionQuote else { return false }
        return reasonText.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(quote.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    private var textRequirementMet: Bool {
        if requiresQuoteMatch {
            return textMatchesQuote
        } else {
            return reasonText.count >= 15
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        statsBanner
                            .padding(.top, 16)

                        Spacer(minLength: 32)

                        if let quote = intentionQuote, !quote.isEmpty {
                            quoteSection(quote)
                        }

                        Spacer(minLength: 32)

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
                        countdownTask?.cancel()
                        countdownTask = nil
                        onCancel()
                    }
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    // MARK: - Stats banner

    private var statsBanner: some View {
        HStack(spacing: 10) {
            statBox(value: "\(streakDays ?? 0)", unit: "days", label: "STREAK")
            if let timeText = timeUntilFreeTimeText {
                statBox(value: timeText, unit: nil, label: "BLOCKING ENDS IN")
            } else {
                statBox(value: "Free Time", unit: nil, label: "RIGHT NOW")
            }
        }
    }

    private func statBox(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.text)
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(AppConstants.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppConstants.Colors.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Quote section

    private func quoteSection(_ quote: String) -> some View {
        Text("\u{201C}\(quote)\u{201D}")
            .font(.title3)
            .italic()
            .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.9))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }

    // MARK: - Action Section (reason input)

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(requiresQuoteMatch ? "Type your intention to confirm" : "Why unlock?")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppConstants.Colors.text)
                .padding(.bottom, 14)

            TextField(requiresQuoteMatch ? "Type it here..." : "Write your reason...", text: $reasonText)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit { isTextFieldFocused = false }
                .onChange(of: reasonText) { _, _ in
                    if textRequirementMet && countdownEndDate == nil {
                        startCountdown()
                    }
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppConstants.Colors.textSecondary.opacity(0.15))
                        .frame(height: 0.5)
                }

            Group {
                if requiresQuoteMatch {
                    if textMatchesQuote {
                        Text("Matched")
                            .foregroundColor(AppConstants.Colors.text.opacity(0.5))
                    } else {
                        Text("\(reasonText.count)/\(intentionQuote?.count ?? 0)")
                            .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.5))
                    }
                } else {
                    Text("\(reasonText.count)/15")
                        .foregroundColor(AppConstants.Colors.textSecondary.opacity(0.5))
                }
            }
            .font(.caption)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Progress Bar Button

    private var progressButton: some View {
        Button(action: { onConfirm() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppConstants.Colors.textSecondary.opacity(0.15))

                // Fill grows leading→trailing via scaleEffect, animated by the
                // `.animation(_:value:)` modifier whenever animatedProgress changes.
                // scaleEffect is reliably animatable; using GeometryReader + frame
                // can lose animation context.
                RoundedRectangle(cornerRadius: 12)
                    .fill(isConfirmEnabled
                          ? AppConstants.Colors.text
                          : AppConstants.Colors.text.opacity(0.35))
                    .scaleEffect(x: animatedProgress, y: 1, anchor: .leading)
                    .animation(.linear(duration: countdownDuration), value: animatedProgress)

                // TimelineView only for the seconds label — 4Hz is enough since
                // text changes at most once per second.
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(currentLabel(at: context.date))
                        .font(.headline)
                        .foregroundColor(isConfirmEnabled
                                        ? AppConstants.Colors.background
                                        : AppConstants.Colors.textSecondary)
                }
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
        textRequirementMet && isCountdownComplete
    }

    private func currentLabel(at date: Date) -> String {
        guard let end = countdownEndDate, !isCountdownComplete else { return "Disable" }
        let remaining = max(0, end.timeIntervalSince(date))
        let seconds = Int(ceil(remaining))
        return seconds > 0 ? "Disable · \(seconds)s" : "Disable"
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownTask?.cancel()
        countdownEndDate = Date().addingTimeInterval(countdownDuration)
        isCountdownComplete = false

        // Drive the fill: setting animatedProgress to 1.0 triggers the
        // .animation(.linear(duration: countdownDuration), value:) modifier
        // on the fill rectangle, interpolating 0 → 1 over the countdown.
        animatedProgress = 1.0

        countdownTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(countdownDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isCountdownComplete = true
        }
    }
}

// MARK: - Preview

#Preview {
    DisableBlockingConfirmationView(
        streakDays: 6,
        timeUntilFreeTimeText: "1h 48m",
        intentionQuote: "I want to be more present with my family.",
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}
