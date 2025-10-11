//
//  ShieldConfigurationExtension.swift
//  IntentionsShieldConfiguration
//
//  Created by Kieran Hitchcock on 04/10/2025.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Shield Configuration Extension that provides custom shield appearances
/// for blocked applications and websites with Intentions branding and inspirational messaging
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Application Shield Configuration

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return createMinimalShieldConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return createMinimalShieldConfiguration()
    }

    // MARK: - Web Domain Shield Configuration

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return createMinimalShieldConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return createMinimalShieldConfiguration()
    }

    // MARK: - Helper Methods

    /// Creates a minimal shield configuration with app icon and inspirational message
    private func createMinimalShieldConfiguration() -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.black,
            icon: createRoundedIcon(),
            title: ShieldConfiguration.Label(
                text: "Blocked by Intent",
                color: UIColor.white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\nBe intentional with your energy.\nBe intentional with your time.\nBe intentional with your habits.",
                color: UIColor.white
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: UIColor.white
            ),
            primaryButtonBackgroundColor: UIColor.black
        )
    }

    /// Creates a rounded version of the app icon
    private func createRoundedIcon() -> UIImage? {
        guard let originalImage = UIImage(named: "AppIcon") else { return nil }

        let size = CGSize(width: 60, height: 60)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.2)
            path.addClip()
            originalImage.draw(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }
}
