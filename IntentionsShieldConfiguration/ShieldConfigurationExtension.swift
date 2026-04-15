//
//  ShieldConfigurationExtension.swift
//  IntentionsShieldConfiguration
//
//  Created by Kieran Hitchcock on 04/10/2025.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Shield configuration for blocked apps and web domains.
///
/// Layout ("Whisper"): ensō glyph, a two-line haiku title, and the user's
/// personal intention quote as a subtitle attribution. Falls back to a generic
/// three-line body when no quote has been set.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private enum Shared {
        static let appGroupId = "group.oh.Intent"
        static let intentionQuoteKey = "intentions.shield.intentionQuote"
    }

    // MARK: - Application

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        buildShieldConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        buildShieldConfiguration()
    }

    // MARK: - Web domain

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        buildShieldConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        buildShieldConfiguration()
    }

    // MARK: - Composition

    private func buildShieldConfiguration() -> ShieldConfiguration {
        let background = UIColor(white: 0.078, alpha: 1.0)   // #141414
        let textPrimary = UIColor.white
        let textSecondary = UIColor(white: 0.6, alpha: 1.0)  // #999999
        let buttonBackground = UIColor(white: 0.145, alpha: 1.0) // #252525

        let title = ShieldConfiguration.Label(
            text: "Be intentional\nwith this moment.",
            color: textPrimary
        )

        let subtitle = ShieldConfiguration.Label(
            text: subtitleText(),
            color: textSecondary
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: background,
            icon: ensoIcon(),
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Return",
                color: textPrimary
            ),
            primaryButtonBackgroundColor: buttonBackground
        )
    }

    private func subtitleText() -> String {
        if let quote = storedIntentionQuote() {
            return "———\n\n\(quote)"
        }
        return "Be intentional with your energy.\nBe intentional with your time.\nBe intentional with your habits."
    }

    private func storedIntentionQuote() -> String? {
        guard let shared = UserDefaults(suiteName: Shared.appGroupId) else { return nil }
        let raw = shared.string(forKey: Shared.intentionQuoteKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    // MARK: - Ensō glyph

    /// Renders the Intent ensō as a UIImage suitable for `ShieldConfiguration.icon`.
    ///
    /// Faithful port of the canonical logo defined in
    /// `docs/superpowers/specs/2026-04-11-app-icon-redesign-design.md` — four
    /// cubic-Bezier segments (hand-drawn brush shape, not a perfect circle),
    /// #bbbbbb stroke at 7.5 units on a 100-unit viewBox, #dddddd dot
    /// (rx 5.5, ry 5) anchored at (50, 51) and rotated -12° around that point.
    private func ensoIcon() -> UIImage {
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let s = size.width / 100.0  // spec viewBox is 100×100

            // Brush stroke — 4 cubic segments, gap left open top-right.
            let path = CGMutablePath()
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

            cg.setStrokeColor(UIColor(white: 0xBB / 255.0, alpha: 1.0).cgColor)
            cg.setLineWidth(7.5 * s)
            cg.setLineCap(.round)
            cg.addPath(path)
            cg.strokePath()

            // Dot — ellipse at (50, 51), rx 5.5, ry 5, rotated -12° around (50, 51).
            let dotCenter = CGPoint(x: 50 * s, y: 51 * s)
            cg.saveGState()
            cg.translateBy(x: dotCenter.x, y: dotCenter.y)
            cg.rotate(by: -12 * .pi / 180)
            let dotRect = CGRect(
                x: -5.5 * s,
                y: -5.0 * s,
                width: 11.0 * s,
                height: 10.0 * s
            )
            cg.setFillColor(UIColor(white: 0xDD / 255.0, alpha: 1.0).cgColor)
            cg.fillEllipse(in: dotRect)
            cg.restoreGState()
        }.withRenderingMode(.alwaysOriginal)
    }
}
