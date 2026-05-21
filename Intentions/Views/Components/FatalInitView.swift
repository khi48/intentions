//
//  FatalInitView.swift
//  Intentions
//
//  Full-screen non-dismissible failure surface for `ContentViewModel.init()`
//  throws (see #49). Replaces the prior mock-fallback path that ran the app
//  against MockServices and surfaced a single dismissible alert — that path
//  let users interact with a UI that didn't actually persist or block.
//
//  Triggers:
//    - App Group `UserDefaults(suiteName:)` returns nil (provisioning bug)
//    - SwiftData `ModelContainer` init throws (corrupted store / disk full)
//
//  Neither case is user-recoverable in-app. Surface a diagnostic copy + a
//  support contact path.
//

import SwiftUI

struct FatalInitView: View {
    let diagnostic: String

    private let supportEmail = "kieran.hitchcock@rocketmail.com"

    @State private var copied = false

    var body: some View {
        ZStack {
            AppConstants.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "exclamationmark.octagon")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(AppConstants.Colors.textSecondary)

                VStack(spacing: 12) {
                    Text("Intent can't start on this device")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppConstants.Colors.text)
                        .multilineTextAlignment(.center)

                    Text("The app's data store failed to initialise. This usually means a corrupted install or a missing entitlement. Please reinstall the app or contact support.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostic")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppConstants.Colors.textSecondary)
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .foregroundColor(AppConstants.Colors.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppConstants.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 10) {
                    Button(action: copyDiagnostic) {
                        Text(copied ? "Copied" : "Copy diagnostic")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppConstants.Colors.text)
                            .foregroundColor(AppConstants.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: openSupportMail) {
                        Text("Contact support")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppConstants.Colors.surface)
                            .foregroundColor(AppConstants.Colors.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private func copyDiagnostic() {
        UIPasteboard.general.string = diagnostic
        copied = true
    }

    private func openSupportMail() {
        let subject = "Intent — fatal init failure"
        let body = "Diagnostic:\n\(diagnostic)"
        guard let url = URL(string: "mailto:\(supportEmail)?subject=\(subject.urlEncoded)&body=\(body.urlEncoded)") else { return }
        UIApplication.shared.open(url)
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

#Preview {
    FatalInitView(diagnostic: "Failed to open App Group UserDefaults for suite group.com.intentions.shared.")
}
