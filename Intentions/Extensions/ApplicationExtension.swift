//
//  ApplicationExtension.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 16/06/2025.
//

import FamilyControls
import ManagedSettings

// Family Controls Sendable Extensions
// These extensions enable Family Controls types to work with Swift 6 strict concurrency

// Make the generic Token type Sendable - covers both ApplicationToken and ActivityCategoryToken
extension Token: @unchecked @retroactive Sendable {}
