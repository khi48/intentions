//
//  AppGroupsView.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import SwiftUI

/// Placeholder view for app groups management
/// This will be implemented in a future task
struct AppGroupsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("App Groups")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Create and manage collections of apps for quick session setup")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Coming Soon")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    AppGroupsView()
}