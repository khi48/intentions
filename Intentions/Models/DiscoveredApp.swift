//
//  DiscoveredApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//
// =============================================================================
// Models/DiscoveredApp.swift - App Discovery Data Model
// =============================================================================

import Foundation
import FamilyControls
import ManagedSettings

struct DiscoveredApp: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
    let bundleIdentifier: String
    let applicationToken: ApplicationToken
    let category: String?
    let isSystemApp: Bool
    
    init(displayName: String, bundleIdentifier: String, token: ApplicationToken,
         category: String? = nil, isSystemApp: Bool = false) {
        self.id = UUID()
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationToken = token
        self.category = category
        self.isSystemApp = isSystemApp
    }
    
    // Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: DiscoveredApp, rhs: DiscoveredApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
    
    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, displayName, bundleIdentifier, applicationToken, category, isSystemApp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        applicationToken = try container.decode(ApplicationToken.self, forKey: .applicationToken)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        isSystemApp = try container.decode(Bool.self, forKey: .isSystemApp)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(applicationToken, forKey: .applicationToken)
        try container.encode(category, forKey: .category)
        try container.encode(isSystemApp, forKey: .isSystemApp)
    }
}

