//
//  QuickAction.swift
//  Intentions
//
//  Created by Claude on 03/09/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls

/// Represents a quick action that users can create for fast session initiation
/// Quick actions are pre-configured sessions with specific app groups, durations, and settings
struct QuickAction: Identifiable, Codable, Sendable {
    
    // MARK: - Properties
    
    /// Unique identifier for this quick action
    let id: UUID
    
    /// Display name for the quick action
    var name: String
    
    /// Optional subtitle/description for the quick action
    var subtitle: String?
    
    /// SF Symbol icon name for visual representation
    var iconName: String
    
    /// Color theme for the quick action (stored as hex string)
    private var _colorHex: String
    
    /// Session duration in seconds
    var duration: TimeInterval
    
    /// Associated app group IDs for this quick action
    var appGroupIds: Set<UUID>
    
    /// Additional individual applications (not in groups) - temporarily disabled
    // var individualApplications: Set<ApplicationToken>
    
    /// Additional individual categories (not in groups) - temporarily disabled  
    // var individualCategories: Set<ActivityCategoryToken>
    
    /// Whether this quick action is enabled/active
    var isEnabled: Bool
    
    /// Creation timestamp
    let createdAt: Date
    
    /// Last modification timestamp
    var lastModified: Date
    
    /// Usage count for analytics and ordering
    var usageCount: Int
    
    /// Last used timestamp for analytics
    var lastUsed: Date?
    
    // MARK: - Computed Properties
    
    /// Color representation of the stored hex color
    var color: Color {
        Color(hex: _colorHex) ?? .blue
    }
    
    /// Set the color for this quick action
    mutating func setColor(_ color: Color) {
        _colorHex = color.toHex() ?? "#007AFF"
        lastModified = Date()
    }
    
    /// Formatted duration string for display
    var formattedDuration: String {
        if duration >= 3600 {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            let minutes = Int(duration) / 60
            return "\(minutes)m"
        }
    }
    
    /// Whether this quick action has any content (apps or categories)
    var hasContent: Bool {
        !appGroupIds.isEmpty
    }
    
    // MARK: - Initialization
    
    /// Initialize a new quick action
    /// - Parameters:
    ///   - name: Display name for the quick action
    ///   - subtitle: Optional subtitle/description
    ///   - iconName: SF Symbol icon name
    ///   - color: Color theme for the action
    ///   - duration: Session duration in seconds
    ///   - appGroupIds: Associated app group IDs
    init(
        name: String,
        subtitle: String? = nil,
        iconName: String = "star.fill",
        color: Color = .blue,
        duration: TimeInterval = AppConstants.Session.defaultDuration,
        appGroupIds: Set<UUID> = []
    ) {
        self.id = UUID()
        self.name = name
        self.subtitle = subtitle
        self.iconName = iconName
        self._colorHex = color.toHex() ?? "#007AFF"
        self.duration = duration
        self.appGroupIds = appGroupIds
        self.isEnabled = true
        self.createdAt = Date()
        self.lastModified = Date()
        self.usageCount = 0
        self.lastUsed = nil
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id, name, subtitle, iconName, _colorHex, duration
        case appGroupIds
        case isEnabled, createdAt, lastModified, usageCount, lastUsed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        iconName = try container.decode(String.self, forKey: .iconName)
        _colorHex = try container.decode(String.self, forKey: ._colorHex)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        appGroupIds = try container.decode(Set<UUID>.self, forKey: .appGroupIds)
        
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        usageCount = try container.decode(Int.self, forKey: .usageCount)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(iconName, forKey: .iconName)
        try container.encode(_colorHex, forKey: ._colorHex)
        try container.encode(duration, forKey: .duration)
        try container.encode(appGroupIds, forKey: .appGroupIds)
        
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(usageCount, forKey: .usageCount)
        try container.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
    
    // MARK: - Action Methods
    
    /// Update the quick action properties
    mutating func update(
        name: String? = nil,
        subtitle: String? = nil,
        iconName: String? = nil,
        color: Color? = nil,
        duration: TimeInterval? = nil,
        appGroupIds: Set<UUID>? = nil
    ) {
        if let name = name { self.name = name }
        if let subtitle = subtitle { self.subtitle = subtitle }
        if let iconName = iconName { self.iconName = iconName }
        if let color = color { self.setColor(color) }
        if let duration = duration { self.duration = duration }
        if let appGroupIds = appGroupIds { self.appGroupIds = appGroupIds }
        
        lastModified = Date()
    }
    
    /// Record usage of this quick action
    mutating func recordUsage() {
        usageCount += 1
        lastUsed = Date()
        lastModified = Date()
    }
    
    /// Toggle enabled state
    mutating func toggleEnabled() {
        isEnabled.toggle()
        lastModified = Date()
    }
    
    /// Create an IntentionSession from this quick action
    /// - Parameter appGroups: Available app groups to resolve IDs
    /// - Returns: Configured IntentionSession
    func createSession(with appGroups: [AppGroup]) throws -> IntentionSession {
        // Collect all applications and categories from referenced app groups  
        var resolvedGroupIds: [UUID] = []
        
        for groupId in appGroupIds {
            if appGroups.contains(where: { $0.id == groupId }) {
                resolvedGroupIds.append(groupId)
            }
        }
        
        // Create session with comprehensive blocking - collect tokens from app groups
        return try IntentionSession(
            appGroups: resolvedGroupIds,
            duration: duration
        )
    }
}

// MARK: - Hashable & Equatable

extension QuickAction: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Extensions

extension Color {
    /// Convert Color to hex string representation
    func toHex() -> String? {
        guard let components = cgColor?.components else { return nil }
        
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        
        return String(format: "#%02lX%02lX%02lX", 
                     lroundf(r * 255),
                     lroundf(g * 255),
                     lroundf(b * 255))
    }
    
    /// Initialize Color from hex string
    init?(hex: String) {
        var hexFormatted = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
        
        guard hexFormatted.count == 6 else { return nil }
        
        var rgbValue: UInt64 = 0
        Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
        
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}