//
//  BannerError.swift
//  Intentions
//
//  Typed app-level error surfaced via AppErrorBanner. Replaces the prior
//  `errorMessage: String?` + .alert("OK") pattern with classified recovery
//  actions (retry the failed call, or deep-link to iOS Settings). See #49.
//

import Foundation

struct BannerError: Sendable {
    let message: String
    let action: Action

    enum Action: Sendable {
        case retry(@Sendable () async -> Void)
        case openSettings
    }
}
