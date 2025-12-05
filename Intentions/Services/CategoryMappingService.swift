//
//  CategoryMappingService.swift
//  Intentions
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftUI
import ManagedSettings
@preconcurrency import FamilyControls

/// Service for managing app-to-category mappings through extended setup process
/// Maps ApplicationTokens to their respective categories by having users select categories individually
@MainActor
final class CategoryMappingService: Sendable {
    
    // MARK: - Category Definitions
    
    /// Simplified app categories for smart blocking prioritization
    enum AppCategory: String, CaseIterable, Sendable {
        case social = "Social"
        case games = "Games"
        case entertainment = "Entertainment"
        case creativity = "Creativity"
        case education = "Education"
        case healthFitness = "Health & Fitness"
        case informationReading = "Information & Reading"
        case productivityFinance = "Productivity & Finance"
        case shoppingFood = "Shopping & Food"
        case travel = "Travel"
        case utilities = "Utilities"
        case other = "Other"
        
        /// Priority for blocking - lower numbers get blocked first when hitting API limits
        var blockingPriority: Int {
            switch self {
            case .social: return 1  // Highest priority - most distracting
            case .games: return 2
            case .entertainment: return 3
            case .creativity: return 4
            case .education: return 5
            case .healthFitness: return 6
            case .informationReading: return 7
            case .productivityFinance: return 8
            case .shoppingFood: return 9
            case .travel: return 10
            case .utilities: return 11
            case .other: return 12  // Lowest priority
            }
        }
        
        var displayName: String { rawValue }
        
        var description: String {
            switch self {
            case .social: return "Social media and messaging"
            case .games: return "All types of games and gaming"
            case .entertainment: return "Movies, TV, streaming, videos"
            case .creativity: return "Art, design, photo/video editing"
            case .education: return "Learning, courses, educational content"
            case .healthFitness: return "Health tracking, fitness, wellness"
            case .informationReading: return "News, books, articles, research"
            case .productivityFinance: return "Work tools, banking, budgeting"
            case .shoppingFood: return "Shopping, food delivery, recipes"
            case .travel: return "Maps, travel planning, navigation"
            case .utilities: return "Tools, calculators, system utilities"
            case .other: return "Uncategorized and miscellaneous apps"
            }
        }
        
        var iconName: String {
            switch self {
            case .social: return "heart.fill"                    // Pink heart like Apple's Social
            case .games: return "rocket.fill"                   // Blue rocket like Apple's Games
            case .entertainment: return "popcorn.fill"          // Red/orange popcorn like Apple's Entertainment
            case .creativity: return "paintbrush.fill"          // Yellow/orange paintbrush like Apple's Creativity
            case .productivityFinance: return "airplane"        // Blue airplane like Apple's Productivity & Finance
            case .education: return "globe"                     // Green/blue globe like Apple's Education
            case .informationReading: return "book.fill"        // Blue book like Apple's Information & Reading
            case .healthFitness: return "figure.run"           // Blue figure like Apple's Health & Fitness
            case .utilities: return "hammer.fill"               // Gray hammer like Apple's Utilities
            case .shoppingFood: return "bag.fill"              // Orange bag like Apple's Shopping & Food
            case .travel: return "car.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .social: return Color(red: 1.0, green: 0.4, blue: 0.6)        // Apple's pink
            case .games: return Color(red: 0.0, green: 0.5, blue: 1.0)         // Apple's blue rocket
            case .entertainment: return Color(red: 1.0, green: 0.3, blue: 0.0)  // Apple's red-orange
            case .creativity: return Color(red: 1.0, green: 0.8, blue: 0.0)     // Apple's yellow-orange
            case .productivityFinance: return Color(red: 0.0, green: 0.5, blue: 1.0) // Apple's blue
            case .education: return Color(red: 0.0, green: 0.7, blue: 0.4)      // Apple's green
            case .informationReading: return Color(red: 0.0, green: 0.5, blue: 1.0) // Apple's blue
            case .healthFitness: return Color(red: 0.0, green: 0.7, blue: 1.0)  // Apple's cyan-blue
            case .utilities: return Color(red: 0.5, green: 0.5, blue: 0.5)      // Apple's gray
            case .shoppingFood: return Color(red: 1.0, green: 0.5, blue: 0.0)   // Apple's orange
            case .travel: return Color(red: 0.0, green: 0.5, blue: 1.0)         // Blue
            case .other: return Color(red: 0.5, green: 0.5, blue: 0.5)          // Gray
            }
        }

        /// Custom image asset name for extracted Apple FamilyActivityPicker icons
        /// Return nil to use SF Symbol fallback
        var customImageName: String? {
            switch self {
            case .social: return "apple-social-icon"           // Pink heart from Apple
            case .games: return "apple-games-icon"             // Blue rocket from Apple
            case .entertainment: return "apple-entertainment-icon" // Orange popcorn from Apple
            case .creativity: return "apple-creativity-icon"   // Yellow paintbrush from Apple
            case .productivityFinance: return "apple-productivity-icon" // Blue airplane from Apple
            case .education: return "apple-education-icon"     // Green globe from Apple
            case .informationReading: return "apple-reading-icon" // Blue book from Apple
            case .healthFitness: return "apple-health-icon"    // Blue figure from Apple
            case .utilities: return "apple-utilities-icon"     // Gray tools from Apple
            case .shoppingFood: return "apple-shopping-icon"   // Orange bag from Apple
            case .travel: return "apple-travel-icon"           // Blue car/travel from Apple
            case .other: return "apple-other-icon"             // Custom other category icon
            }
        }
    }
    
    // MARK: - Storage
    
    /// Mapping from our custom category to the apps in that category
    private var categoryToAppsMapping: [AppCategory: Set<ApplicationToken>] = [:]
    
    /// Mapping from our custom category to the actual ActivityCategoryToken (if available)
    private var categoryToTokenMapping: [AppCategory: ActivityCategoryToken] = [:]
    
    /// Whether the setup process has been completed
    private(set) var isSetupCompleted: Bool = false
    
    /// Setup progress tracking
    private(set) var setupProgress: [AppCategory: Bool] = [:]
    
    // MARK: - Setup Progress
    
    /// Get categories that still need to be set up
    var pendingCategories: [AppCategory] {
        AppCategory.allCases.filter { !setupProgress[$0, default: false] }
    }
    
    /// Get categories that have been completed
    var completedCategories: [AppCategory] {
        AppCategory.allCases.filter { setupProgress[$0, default: false] }
    }
    
    /// Overall setup completion percentage
    var setupCompletionPercentage: Double {
        let completed = completedCategories.count
        let total = AppCategory.allCases.count
        return total > 0 ? Double(completed) / Double(total) : 0.0
    }
    
    /// Check if the setup is truly complete (including app mappings)
    /// This addresses the iOS ApplicationToken persistence bug
    var isTrulySetupCompleted: Bool {
        guard isSetupCompleted else { return false }
        
        // Verify that we actually have app mappings
        let totalMappedApps = categoryToAppsMapping.values.reduce(0) { $0 + $1.count }
        return totalMappedApps > 0
    }
    
    // MARK: - Initialization
    
    init() {
        loadFromStorage()
    }
    
    // MARK: - Setup Process
    
    /// Record the result of selecting a specific category
    /// This is called after user selects apps from a single category in FamilyActivityPicker
    func recordCategoryMapping(_ category: AppCategory, selection: FamilyActivitySelection) {
        print("\n" + String(repeating: "=", count: 60))
        // print("📂 CATEGORY MAPPING: Recording \(category.displayName)")
        print(String(repeating: "=", count: 60))
        
        // Extract app tokens from the selection
        let appTokens = Set(selection.applications.compactMap { $0.token })
        let categoryTokens = selection.categories.compactMap { $0.token }

        print("📊 SELECTION ANALYSIS:")
        print("   - Category: \(category.displayName)")
        print("   - Individual apps found: \(appTokens.count)")
        print("   - Category tokens found: \(categoryTokens.count)")
        print("   - includeEntireCategory was: \(selection.includeEntireCategory)")
        
        // Store the app mapping
        if !appTokens.isEmpty {
            categoryToAppsMapping[category] = appTokens
            print("✅ APPS MAPPED: \(appTokens.count) apps mapped to \(category.displayName)")
            
            // Debug: Show some token examples
            for (index, token) in appTokens.enumerated().prefix(3) {
                print("   - App Token \(index + 1): \(token)")
            }
            if appTokens.count > 3 {
                print("   - ... and \(appTokens.count - 3) more app tokens")
            }
        } else {
            print("⚠️ NO APPS: No individual app tokens found for \(category.displayName)")
        }
        
        // Store category token if available
        if let firstCategoryToken = categoryTokens.first {
            categoryToTokenMapping[category] = firstCategoryToken
            print("✅ CATEGORY TOKEN: Stored category token for \(category.displayName)")
        } else {
            print("⚠️ NO CATEGORY TOKEN: No category token found for \(category.displayName)")
        }
        
        // Mark category as completed
        setupProgress[category] = true
        print("✅ PROGRESS: \(category.displayName) marked as completed")
        print("📈 OVERALL PROGRESS: \(completedCategories.count)/\(AppCategory.allCases.count) categories completed")
        
        // Check if setup is complete
        updateSetupCompletion()
        
        // Save to storage
        saveToStorage()
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    /// Check and update overall setup completion status
    private func updateSetupCompletion() {
        let wasCompleted = isSetupCompleted
        
        // Require ALL categories to be mapped for complete setup
        let totalCategoriesCount = AppCategory.allCases.count
        let completedCategoriesCount = completedCategories.count
        let totalMappedApps = categoryToAppsMapping.values.reduce(0) { $0 + $1.count }
        let minimumAppsRequired = 5  // Require at least 5 total apps to be mapped (ensures real mapping occurred)
        
        isSetupCompleted = completedCategoriesCount == totalCategoriesCount && 
                          totalMappedApps >= minimumAppsRequired
        
        if !wasCompleted && isSetupCompleted {
            print("🎉 SETUP COMPLETE: All \(completedCategoriesCount) categories and \(totalMappedApps) apps mapped!")
            printCompleteMappingSummary()
        } else if !isSetupCompleted {
            print("📋 SETUP PROGRESS: \(completedCategoriesCount)/\(totalCategoriesCount) categories completed (\(totalMappedApps) apps)")
        }
    }
    
    /// Force setup completion even if not all categories are mapped
    /// Used when user chooses to finish setup with partial mapping
    func forceSetupCompleted() {
        let wasCompleted = isSetupCompleted
        isSetupCompleted = true
        
        if !wasCompleted {
            print("🎉 SETUP FORCED COMPLETE: User chose to finish with partial mapping!")
            printCompleteMappingSummary()
        }
        
        // Save the forced completion state
        saveToStorage()
    }

    /// Retry validation of setup completion after app initialization delay
    /// This addresses the iOS ApplicationToken loading delay issue
    /// Only reloads if mappings are currently empty (to avoid redundant loading)
    func retrySetupValidation() {
        guard isSetupCompleted else { return }

        // Check if we already have mappings loaded
        let currentMappedApps = categoryToAppsMapping.values.reduce(0) { $0 + $1.count }

        if currentMappedApps > 0 {
            print("✅ RETRY SKIPPED: Category mappings already loaded - \(currentMappedApps) apps present")
            return
        }

        // Mappings are empty - this could be a transient iOS loading issue
        print("🔄 RETRY: Mappings empty, reloading after initialization delay...")
        loadCategoryMappings()

        let totalMappedApps = categoryToAppsMapping.values.reduce(0) { $0 + $1.count }
        if totalMappedApps == 0 {
            print("🚨 RETRY FAILED: Still no app mappings after delay - forcing setup reset")
            print("🔄 This indicates actual ApplicationToken expiration, not just loading delay")

            // Now reset setup completion since retry failed
            isSetupCompleted = false
            setupProgress.removeAll()

            // Update storage
            UserDefaults.standard.set(false, forKey: "category_mapping_setup_completed")
            UserDefaults.standard.removeObject(forKey: "category_mapping_setup_progress")

            // Clear any corrupted mapping data
            clearStoredMappings()

            print("❌ FORCED RESET: User will need to complete category mapping again")
        } else {
            print("✅ RETRY SUCCESS: Category mappings loaded after delay - \(totalMappedApps) apps found")
        }
    }
    
    /// Print a comprehensive summary of all mappings
    private func printCompleteMappingSummary() {
        print("\n" + String(repeating: "🎊", count: 30))
        print("COMPLETE CATEGORY MAPPING SUMMARY")
        print(String(repeating: "🎊", count: 30))
        
        let sortedCategories = AppCategory.allCases.sorted { $0.blockingPriority < $1.blockingPriority }
        
        var totalApps = 0
        for category in sortedCategories {
            let appCount = categoryToAppsMapping[category]?.count ?? 0
            let hasToken = categoryToTokenMapping[category] != nil
            totalApps += appCount
            
            print("📂 \(category.displayName):")
            print("   - Apps: \(appCount)")
            print("   - Has Category Token: \(hasToken ? "✅" : "❌")")
            print("   - Blocking Priority: \(category.blockingPriority) (lower = blocked first)")
        }
        
        print("\n📊 TOTALS:")
        print("   - Categories Mapped: \(completedCategories.count)")
        print("   - Total Apps Discovered: \(totalApps)")
        print("   - Ready for Smart Blocking: ✅")
        
        print(String(repeating: "🎊", count: 30) + "\n")
    }
    
    // MARK: - Query Methods
    
    /// Get all apps that belong to a specific category
    func getApps(for category: AppCategory) -> Set<ApplicationToken> {
        return categoryToAppsMapping[category] ?? []
    }
    
    /// Get the category token for a specific category (if available)
    func getCategoryToken(for category: AppCategory) -> ActivityCategoryToken? {
        let token = categoryToTokenMapping[category]
        print("🔍 GET TOKEN: \(category.displayName) - Has token: \(token != nil)")
        return token
    }
    
    /// Get apps prioritized by blocking priority (most distracting first)
    func getAppsPrioritizedForBlocking() -> [(category: AppCategory, apps: Set<ApplicationToken>)] {
        let sortedCategories = AppCategory.allCases.sorted { $0.blockingPriority < $1.blockingPriority }
        
        return sortedCategories.compactMap { category in
            guard let apps = categoryToAppsMapping[category], !apps.isEmpty else { return nil }
            return (category: category, apps: apps)
        }
    }
    
    /// Get a prioritized list of apps to block, up to the specified limit
    func getPrioritizedAppsToBlock(from allAppsToBlock: Set<ApplicationToken>, limit: Int) -> Set<ApplicationToken> {
        guard allAppsToBlock.count > limit else { return allAppsToBlock }
        
        print("\n🧠 SMART PRIORITIZATION WITH CATEGORY MAPPING:")
        print("   - Total apps to block: \(allAppsToBlock.count)")
        print("   - API limit: \(limit)")
        print("   - Using category-based prioritization")
        
        var selectedApps: Set<ApplicationToken> = []
        let prioritizedCategories = getAppsPrioritizedForBlocking()
        
        for (category, categoryApps) in prioritizedCategories {
            // Find apps in this category that need to be blocked
            let categoryAppsToBlock = categoryApps.intersection(allAppsToBlock)
            
            if !categoryAppsToBlock.isEmpty {
                let availableSlots = limit - selectedApps.count
                if availableSlots <= 0 { break }
                
                let appsToAdd = Set(categoryAppsToBlock.prefix(availableSlots))
                selectedApps.formUnion(appsToAdd)
                
                print("   - \(category.displayName): Added \(appsToAdd.count) apps (Priority \(category.blockingPriority))")
                
                if selectedApps.count >= limit { break }
            }
        }
        
        // Fill remaining slots with unmapped apps if needed
        if selectedApps.count < limit {
            let unmappedApps = allAppsToBlock.subtracting(selectedApps)
            let remainingSlots = limit - selectedApps.count
            let additionalApps = Set(unmappedApps.prefix(remainingSlots))
            selectedApps.formUnion(additionalApps)
            
            if !additionalApps.isEmpty {
                print("   - Unmapped apps: Added \(additionalApps.count) additional apps")
            }
        }
        
        print("   - Final selection: \(selectedApps.count) apps prioritized by category")
        return selectedApps
    }
    
    /// Get all apps for selected categories (for session creation)
    /// This is used when user selects categories they want to keep accessible during their session
    func getAppsForCategories(_ categories: Set<AppCategory>) -> Set<ApplicationToken> {
        var allApps: Set<ApplicationToken> = []
        
        print("\n📂 GETTING APPS FOR SELECTED CATEGORIES:")
        for category in categories {
            let categoryApps = getApps(for: category)
            allApps.formUnion(categoryApps)
            print("   - \(category.displayName): \(categoryApps.count) apps")
        }
        print("   - Total apps to allow: \(allApps.count)")
        
        return allApps
    }
    
    /// Get summary of all mapped categories with app counts
    func getCategorySummary() -> [(category: AppCategory, appCount: Int)] {
        return AppCategory.allCases.map { category in
            (category: category, appCount: getApps(for: category).count)
        }.filter { $0.appCount > 0 }
    }
    
    /// Analyze which categories contain the user's selected apps and determine blocking strategy
    /// Returns: (categoriesToBlockCompletely, appsToBlockIndividually)
    func analyzeBlockingStrategy(for selectedApps: Set<ApplicationToken>) -> (
        categoriesToBlock: [AppCategory], 
        appsToBlockInUsedCategories: Set<ApplicationToken>
    ) {
        print("\n🧠 ANALYZING BLOCKING STRATEGY:")
        print("   - User selected \(selectedApps.count) apps to allow")
        
        var categoriesToBlockCompletely: [AppCategory] = []
        var appsToBlockIndividually: Set<ApplicationToken> = []
        
        // Analyze each category
        for category in AppCategory.allCases {
            let categoryApps = getApps(for: category)
            print("Category: (\(category.displayName)), number of apps: \(categoryApps.count)")
            let selectedAppsInCategory = categoryApps.intersection(selectedApps)
            
            if selectedAppsInCategory.isEmpty {
                // User didn't select any apps from this category - block the entire category
                print("   - 🚫 \(category.displayName): Block entire category (\(categoryApps.count) apps)")

                if !categoryApps.isEmpty {
                    categoriesToBlockCompletely.append(category)
                    print("   - 🚫 \(category.displayName): Block entire category (\(categoryApps.count) apps)")
                }
            } else {
                // User selected some apps from this category - block individual unselected apps
                let appsToBlockInThisCategory = categoryApps.subtracting(selectedApps)
                appsToBlockIndividually.formUnion(appsToBlockInThisCategory)
                
                print("   - 📱 \(category.displayName): Allow \(selectedAppsInCategory.count) apps, block \(appsToBlockInThisCategory.count) apps individually")
            }
        }
        
        print("\n📊 BLOCKING STRATEGY SUMMARY:")
        print("   - Categories to block completely: \(categoriesToBlockCompletely.count)")
        print("   - Individual apps to block: \(appsToBlockIndividually.count)")
        
        return (categoriesToBlockCompletely, appsToBlockIndividually)
    }
    
    /// Get ActivityCategoryTokens for categories that should be blocked completely
    func getCategoryTokensToBlock(for categories: [AppCategory]) -> Set<ActivityCategoryToken> {
        var tokens: Set<ActivityCategoryToken> = []
        
        for category in categories {
            if let token = getCategoryToken(for: category) {
                tokens.insert(token)
            }
        }
        
        // print("🏷️ CATEGORY TOKENS TO BLOCK: \(tokens.count) category tokens found for \(categories.count) categories")
        return tokens
    }
    
    // MARK: - Storage Management
    
    private func saveToStorage() {
        // Save completion status
        UserDefaults.standard.set(isSetupCompleted, forKey: "category_mapping_setup_completed")
        
        // Save setup progress
        let progressData = setupProgress.mapKeys { $0.rawValue }
        UserDefaults.standard.set(progressData, forKey: "category_mapping_setup_progress")
        
        // SAVE ACTUAL APP MAPPINGS using the same method that worked for app discovery
        // Store each category's FamilyActivitySelection using JSON encoding
        saveCategoryMappings()
        
        print("💾 STORAGE: Category mapping progress and app mappings saved")
    }
    
    /// Save category mappings using JSON encoding (same method that worked for app discovery)
    private func saveCategoryMappings() {
        for (category, apps) in categoryToAppsMapping {
            guard !apps.isEmpty else { continue }
            
            let key = "category_mapping_\(category.rawValue)"
            do {
                // Store the app tokens directly as an array
                let tokenData = try JSONEncoder().encode(Array(apps))
                UserDefaults.standard.set(tokenData, forKey: key)
                print("💾 Saved \(apps.count) app tokens for \(category.displayName)")
            } catch {
                print("❌ Failed to save app tokens for \(category.displayName): \(error)")
            }
        }
        
        // Also save category tokens
        for (category, token) in categoryToTokenMapping {
            let key = "category_token_\(category.rawValue)"
            do {
                let tokenData = try JSONEncoder().encode(token)
                UserDefaults.standard.set(tokenData, forKey: key)
                print("💾 Saved category token for \(category.displayName)")
            } catch {
                print("❌ Failed to save category token for \(category.displayName): \(error)")
            }
        }
    }
    
    private func loadFromStorage() {
        // Load completion status
        isSetupCompleted = UserDefaults.standard.bool(forKey: "category_mapping_setup_completed")
        
        // Load setup progress
        if let progressData = UserDefaults.standard.object(forKey: "category_mapping_setup_progress") as? [String: Bool] {
            setupProgress = progressData.compactMapKeys { AppCategory(rawValue: $0) }
        }
        
        // print("📱 STORAGE: Loaded category mapping state - Setup completed: \(isSetupCompleted)")
        
        // LOAD ACTUAL APP MAPPINGS using the same method that worked for app discovery
        if isSetupCompleted {
            loadCategoryMappings()
            
            let totalMappedApps = categoryToAppsMapping.values.reduce(0) { $0 + $1.count }
            if totalMappedApps == 0 {
                print("⚠️ TRANSIENT ISSUE: Setup marked complete but no app mappings loaded yet")
                print("🔄 This is likely due to iOS ApplicationToken loading delay on startup")
                print("🔄 NOT resetting setup - will retry validation later")

                // Don't immediately reset setup completion - this might be a transient issue
                // The app should retry loading mappings before forcing user through setup again
                print("📱 DEFERRED: Setup validation will be retried when app is fully initialized")
            } else {
                print("✅ App mappings loaded successfully - \(totalMappedApps) apps found across categories")
            }
        }
    }
    
    /// Load category mappings using JSON decoding (same method that worked for app discovery)
    private func loadCategoryMappings() {
        var totalLoadedApps = 0
        var totalLoadedCategories = 0
        
        // Load app mappings for each category
        for category in AppCategory.allCases {
            let key = "category_mapping_\(category.rawValue)"
            if let tokenData = UserDefaults.standard.data(forKey: key) {
                do {
                    let apps = try JSONDecoder().decode([ApplicationToken].self, from: tokenData)
                    
                    // ApplicationTokens are the actual tokens - no need to check .token property
                    let validApps = Set(apps)
                    
                    if !validApps.isEmpty {
                        categoryToAppsMapping[category] = validApps
                        totalLoadedApps += validApps.count
                        // print("📱 Loaded \(validApps.count) valid app tokens for \(category.displayName)")
                    } else {
                        print("⚠️ All app tokens expired for \(category.displayName)")
                        // Remove corrupted data
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                } catch {
                    print("❌ Failed to load app tokens for \(category.displayName): \(error)")
                    // Remove corrupted data
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        
        // Load category tokens
        for category in AppCategory.allCases {
            let key = "category_token_\(category.rawValue)"
            if let tokenData = UserDefaults.standard.data(forKey: key) {
                do {
                    let token = try JSONDecoder().decode(ActivityCategoryToken.self, from: tokenData)
                    
                    // ActivityCategoryTokens are the actual tokens - store them directly
                    categoryToTokenMapping[category] = token
                    totalLoadedCategories += 1
                    print("📱 Loaded valid category token for \(category.displayName)")
                } catch {
                    print("❌ Failed to load category token for \(category.displayName): \(error)")
                    // Remove corrupted data
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        
        print("📊 MAPPING LOAD SUMMARY:")
        print("   - Total apps loaded: \(totalLoadedApps)")
        print("   - Total category tokens loaded: \(totalLoadedCategories)")
        print("   - Categories with apps: \(categoryToAppsMapping.count)")
    }
    
    /// Clear all stored mapping data (for cleanup when corrupted)
    private func clearStoredMappings() {
        for category in AppCategory.allCases {
            UserDefaults.standard.removeObject(forKey: "category_mapping_\(category.rawValue)")
            UserDefaults.standard.removeObject(forKey: "category_token_\(category.rawValue)")
        }
        print("🗑️ Cleared all stored category mappings due to corruption")
    }
    
    /// Reset all category mappings and setup progress
    func resetAllMappings() {
        categoryToAppsMapping.removeAll()
        categoryToTokenMapping.removeAll()
        setupProgress.removeAll()
        isSetupCompleted = false
        
        // Clear storage including the new mapping data
        UserDefaults.standard.removeObject(forKey: "category_mapping_setup_completed")
        UserDefaults.standard.removeObject(forKey: "category_mapping_setup_progress")
        clearStoredMappings()
        
        print("🔄 RESET: All category mappings and storage cleared")
    }
}

// MARK: - Helper Extensions

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        return Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
    
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        return Dictionary<T, Value>(uniqueKeysWithValues: compactMap { key, value in
            guard let newKey = transform(key) else { return nil }
            return (newKey, value)
        })
    }
}
