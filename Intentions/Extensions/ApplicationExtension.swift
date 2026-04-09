//
//  ApplicationExtension.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 16/06/2025.
//

import Foundation
import FamilyControls
import ManagedSettings

// Family Controls Extensions
// These extensions enable Family Controls types to work with Swift 6 strict concurrency and persistence

// Make the generic Token type Sendable - covers both ApplicationToken and ActivityCategoryToken
extension Token: @unchecked @retroactive Sendable {}

// MARK: - Codable Extensions for Persistence
// ApplicationToken and ActivityCategoryToken are already Codable.
// No extensions needed - they support Codable natively.
