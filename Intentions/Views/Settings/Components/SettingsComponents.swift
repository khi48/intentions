//
//  SettingsComponents.swift
//  Intentions
//
//  Shared visual components for the Settings tab and its sub-pages so every
//  child page renders with the same background, row style, and primary button.
//

import SwiftUI

// MARK: - Page background

extension View {
    /// Apply the standard dark background used by every Settings sub-page.
    func settingsPageBackground() -> some View {
        self.background(AppConstants.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Primary action button

/// Full-width filled button used as the main call-to-action on a Settings sub-page
/// (e.g. "Open Settings", "Continue", "Save"). Use this everywhere instead of ad-hoc
/// `Button` styles so all sub-pages match.
struct SettingsPrimaryButton: View {
    let title: String
    let systemImage: String?
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String,
         systemImage: String? = nil,
         isEnabled: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundColor(isEnabled ? AppConstants.Colors.text : AppConstants.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled
                          ? AppConstants.Colors.buttonPrimary
                          : AppConstants.Colors.buttonPrimary.opacity(0.3))
            )
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Section header

/// Bold section title with an underline rule. Used by the main Settings page and
/// any sub-page that groups rows into sections.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(AppConstants.Colors.text)
            Rectangle()
                .fill(AppConstants.Colors.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }
}

// MARK: - Row divider

/// Hairline divider used between rows. Used as a `.overlay(alignment: .bottom)` on
/// each row so the divider hugs the row instead of the parent stack.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppConstants.Colors.textSecondary.opacity(0.15))
            .frame(height: 0.5)
    }
}

// MARK: - Navigation row

/// A tappable row that pushes a destination via a `NavigationLink`. Use for any
/// Settings sub-page entry point. Hits the full padding area, includes the chevron,
/// and shows a hairline divider at the bottom.
struct SettingsNavigationRow<Value: Hashable>: View {
    let title: String
    let value: Value
    let trailingText: String?
    let isDisabled: Bool

    init(_ title: String,
         value: Value,
         trailingText: String? = nil,
         isDisabled: Bool = false) {
        self.title = title
        self.value = value
        self.trailingText = trailingText
        self.isDisabled = isDisabled
    }

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                    .foregroundColor(isDisabled ? AppConstants.Colors.disabled : AppConstants.Colors.text)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.subheadline)
                        .foregroundColor(isDisabled ? AppConstants.Colors.disabled : AppConstants.Colors.textSecondary)
                        .lineLimit(1)
                }
                if !isDisabled {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { SettingsRowDivider() }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Toggle row

/// A row with a title, optional subtitle, and a trailing toggle. Used inside
/// settings sub-pages that need switches (e.g. notification preferences).
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let isOn: Binding<Bool>

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { SettingsRowDivider() }
    }
}

// MARK: - Status row

/// A row that shows a label, a value (right-aligned), and no chevron. Used for
/// non-tappable status displays inside sub-pages (e.g. permission state).
struct SettingsStatusRow: View {
    let title: String
    let value: String
    let valueColor: Color

    init(_ title: String, value: String, valueColor: Color = AppConstants.Colors.textSecondary) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { SettingsRowDivider() }
    }
}

// MARK: - Helper text

/// Caption-sized helper text shown below a row group to explain what the rows do.
struct SettingsHelperText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(AppConstants.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}
