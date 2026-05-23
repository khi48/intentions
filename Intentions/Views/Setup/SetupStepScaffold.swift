//
//  SetupStepScaffold.swift
//  Intentions
//
//  Created by Claude on 23/05/2026.
//

import SwiftUI

/// Shared layout for setup flow steps: optional progress strip on top,
/// scrolling content in the middle, primary footer pinned to the bottom.
/// Use everywhere in the setup flow so every step shares the same shape.
struct SetupStepScaffold<Content: View, Footer: View>: View {

    /// Step number for the 4-dot progress indicator. Pass `nil` to omit the
    /// strip (e.g. the pre-flow welcome card).
    let progressStep: Int?

    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    if let progressStep {
                        SetupProgressStrip(step: progressStep)
                    }
                    content()
                }
                .padding(.horizontal)
                .padding(.top, progressStep == nil ? 24 : 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }

            footer()
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 4-dot horizontal progress strip used at the top of each post-welcome setup step.
struct SetupProgressStrip: View {
    let step: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .fill(step >= i ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppConstants.Colors.text, lineWidth: step == i ? 2 : 0)
                        )
                    if i < 4 {
                        Rectangle()
                            .fill(step > i ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 20)
                    }
                }
            }
            .padding(.horizontal)

            Text("Step \(step) of 4")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
