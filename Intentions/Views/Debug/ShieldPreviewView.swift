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

                Text(subtitleText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var subtitleText: String {
        if let quote = intentionQuote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quote.isEmpty {
            return "———\n\n\(quote)"
        }
        return "Be intentional with your energy.\nBe intentional with your time.\nBe intentional with your habits."
    }
}

// MARK: - Ensō glyph

/// Canonical Intent ensō, ported from the spec SVG
/// (`docs/superpowers/specs/2026-04-11-app-icon-redesign-design.md`).
/// Four cubic Beziers form a hand-drawn brush circle with a wide top-right
/// gap; the dot is an organic ellipse anchored at (50, 51) rotated -12°.
private struct EnsoGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let s = size / 100.0   // spec viewBox 100×100

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 66 * s, y: 22 * s))
                    path.addCurve(
                        to: CGPoint(x: 80 * s, y: 68 * s),
                        control1: CGPoint(x: 84 * s, y: 32 * s),
                        control2: CGPoint(x: 88 * s, y: 52 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 32 * s, y: 82 * s),
                        control1: CGPoint(x: 72 * s, y: 84 * s),
                        control2: CGPoint(x: 48 * s, y: 90 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 20 * s, y: 34 * s),
                        control1: CGPoint(x: 16 * s, y: 74 * s),
                        control2: CGPoint(x: 12 * s, y: 50 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 58 * s, y: 16 * s),
                        control1: CGPoint(x: 27 * s, y: 20 * s),
                        control2: CGPoint(x: 48 * s, y: 14 * s)
                    )
                }
                .stroke(
                    Color(red: 0xBB / 255, green: 0xBB / 255, blue: 0xBB / 255),
                    style: StrokeStyle(lineWidth: 7.5 * s, lineCap: .round)
                )

                Ellipse()
                    .fill(Color(red: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255))
                    .frame(width: 11 * s, height: 10 * s)
                    .rotationEffect(.degrees(-12))
                    .offset(x: 50 * s - (11 * s) / 2, y: 51 * s - (10 * s) / 2)
            }
            .frame(width: size, height: size)
        }
    }
}

#Preview("With quote") {
    ShieldPreviewView(intentionQuote: "To be more present with my family.")
}

#Preview("No quote") {
    ShieldPreviewView(intentionQuote: nil)
}
