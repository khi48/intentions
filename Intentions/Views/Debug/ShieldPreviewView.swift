//
//  ShieldPreviewView.swift
//  Intentions
//
//  Dev-only preview that mirrors the ShieldConfigurationExtension output
//  (colors, icon, title, subtitle, primary button) so the Whisper design can
//  be verified in the simulator without a Family Controls authorisation flow.
//
//  Shown when the app is launched with the `-ShieldPreview` argument.
//

import SwiftUI

struct ShieldPreviewView: View {

    let intentionQuote: String?

    private let background = Color(white: 0.078)        // #141414
    private let textPrimary = Color.white
    private let textSecondary = Color(white: 0.6)       // #999999
    private let buttonBackground = Color(white: 0.145)  // #252525

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                EnsoGlyph()
                    .frame(width: 120, height: 120)
                    .padding(.bottom, 44)

                Text("Be intentional\nwith this moment.")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 16)

                if let quote = trimmedQuote {
                    Text("———")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(textSecondary)
                        .padding(.top, 28)

                    Text(quote)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                } else {
                    Text("Be intentional with your energy.\nBe intentional with your time.\nBe intentional with your habits.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                }

                Spacer(minLength: 0)

                Button(action: {}) {
                    Text("Return")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(buttonBackground)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var trimmedQuote: String? {
        guard let quote = intentionQuote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !quote.isEmpty else { return nil }
        return quote
    }
}

#Preview("With quote") {
    ShieldPreviewView(intentionQuote: "To be more present with my family.")
}

#Preview("No quote") {
    ShieldPreviewView(intentionQuote: nil)
}
