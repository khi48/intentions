//
//  AppGroupsView.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import SwiftUI

/// Main view for app groups management
/// Uses AppGroupListView for the actual implementation
struct AppGroupsView: View {
    let dataService: DataPersisting
    let contentViewModel: ContentViewModel
    @State private var viewModel: AppGroupsViewModel
    
    init(dataService: DataPersisting, contentViewModel: ContentViewModel) {
        self.dataService = dataService
        self.contentViewModel = contentViewModel
        self._viewModel = State(wrappedValue: AppGroupsViewModel(dataService: dataService, contentViewModel: contentViewModel))
    }
    
    var body: some View {
        AppGroupListView(viewModel: viewModel)
    }
}

#Preview {
    AppGroupsView(
        dataService: MockDataPersistenceService(),
        contentViewModel: try! ContentViewModel(dataService: MockDataPersistenceService())
    )
}