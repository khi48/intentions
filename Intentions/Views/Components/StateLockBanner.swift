//
//  StateLockBanner.swift
//  Intentions
//
//  Shared "feature unavailable due to blocking state" banner. Used wherever a
//  user-visible affordance is read-only because of a Blocking on/off / free-time
//  precondition. M4 "edged" design (see issue #39): raised surface panel, plain
//  copy, 2pt accent left rail, ensō glyph.
//
//  Title + remedy compose a single VoiceOver phrase so screen readers announce
//  the banner as one sentence.
//

import SwiftUI

struct StateLockBanner: View {
    let title: String
    let remedy: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EnsoGlyph(
                stroke: AppConstants.Colors.textSecondary,
                dot: AppConstants.Colors.textSecondary
            )
            .frame(width: 18, height: 18)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(AppConstants.Colors.text)
                Text(remedy)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 13)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(remedy)")
    }
}

#Preview("Routines — blocking on") {
    StateLockBanner(
        title: "Schedule locked while blocking is on.",
        remedy: "Turn off blocking in Settings to edit."
    )
    .padding()
    .background(AppConstants.Colors.background)
}

#Preview("Home — blocking off") {
    StateLockBanner(
        title: "Sessions locked while blocking is off.",
        remedy: "Turn on blocking in Settings to start one."
    )
    .padding()
    .background(AppConstants.Colors.background)
}
