//
//  AppErrorBanner.swift
//  Intentions
//
//  App-level error banner replacing the stacked .alert("OK") modals at app
//  root (see #49). Mounted via .safeAreaInset(edge: .top) on MainTabView so
//  it persists across tab switches and pushes content down rather than
//  overlaying it. Style matches ScreenTimeAccessBanner (greyscale surface,
//  leading icon, primary recovery action).
//

import SwiftUI

struct AppErrorBanner: View {
    let error: BannerError
    let onDismiss: () -> Void

    @State private var isRunningRetry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .padding(.top, 1)

                Text(error.message)
                    .font(.footnote)
                    .foregroundColor(AppConstants.Colors.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Spacer()

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .disabled(isRunningRetry)

                Button(action: primaryAction) {
                    HStack(spacing: 6) {
                        if isRunningRetry {
                            ProgressView()
                                .tint(AppConstants.Colors.background)
                                .scaleEffect(0.8)
                        }
                        Text(primaryLabel)
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppConstants.Colors.text)
                    .foregroundColor(AppConstants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isRunningRetry)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppConstants.Colors.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppConstants.Colors.accent)
                .frame(width: 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(error.message). \(primaryLabel) or dismiss.")
    }

    private var primaryLabel: String {
        switch error.action {
        case .retry: return "Retry"
        case .openSettings: return "Open Settings"
        }
    }

    private func primaryAction() {
        switch error.action {
        case .retry(let action):
            isRunningRetry = true
            Task {
                await action()
                isRunningRetry = false
            }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

#Preview("Retry") {
    AppErrorBanner(
        error: BannerError(
            message: "Failed to save schedule. The shield engine did not persist the snapshot.",
            action: .retry { }
        ),
        onDismiss: { }
    )
    .padding(.vertical)
    .background(AppConstants.Colors.background)
}

#Preview("Open Settings") {
    AppErrorBanner(
        error: BannerError(
            message: "Screen Time authorization was denied. Please enable it in Settings to use Intent.",
            action: .openSettings
        ),
        onDismiss: { }
    )
    .padding(.vertical)
    .background(AppConstants.Colors.background)
}
