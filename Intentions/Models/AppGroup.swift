//
//  AppGroup.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//

// =============================================================================
// Models/AppGroup.swift - App Group Data Model
// =============================================================================

import Foundation
import FamilyControls
import ManagedSettings

@Observable
final class AppGroup: Identifiable, Codable, @unchecked Sendable {
    let id: UUID
    var name: String
    var applications: Set<ApplicationToken>
    var categories: Set<ActivityCategoryToken>
    var allowAllWebsites: Bool = false // Whether this group includes access to all websites
    var createdAt: Date
    var lastModified: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        applications: Set<ApplicationToken> = [],
        categories: Set<ActivityCategoryToken> = [],
        allowAllWebsites: Bool = false,
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) throws {
        // Validate input
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.validationFailed("name", reason: "AppGroup name cannot be empty")
        }
        guard name.count <= AppConstants.AppGroup.maxNameLength else {
            throw AppError.validationFailed("name", reason: "AppGroup name exceeds maximum length of \(AppConstants.AppGroup.maxNameLength)")
        }
        guard !AppConstants.AppGroup.reservedNames.contains(name) else {
            throw AppError.validationFailed("name", reason: "AppGroup name '\(name)' is reserved")
        }
        
        self.id = id
        self.name = name
        self.applications = applications
        self.categories = categories
        self.allowAllWebsites = allowAllWebsites
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
    
    // Codable implementation for ApplicationToken and ActivityCategoryToken
    enum CodingKeys: String, CodingKey {
        case id, name, applications, categories, allowAllWebsites, createdAt, lastModified
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)

        // Handle FamilyControls tokens (may need special handling)
        applications = try container.decodeIfPresent(Set<ApplicationToken>.self, forKey: .applications) ?? []
        categories = try container.decodeIfPresent(Set<ActivityCategoryToken>.self, forKey: .categories) ?? []
        allowAllWebsites = try container.decodeIfPresent(Bool.self, forKey: .allowAllWebsites) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(applications, forKey: .applications)
        try container.encode(categories, forKey: .categories)
        try container.encode(allowAllWebsites, forKey: .allowAllWebsites)
    }
    
    func updateModified() {
        lastModified = Date()
    }
}
