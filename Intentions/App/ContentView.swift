//
//  ContentView.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//

import SwiftUI
@preconcurrency import FamilyControls


/// Main app content view with navigation and authorization handling.
///
/// Init-failure handling (#49): `ContentViewModel.init()` can throw if the
/// App Group UserDefaults can't be opened or SwiftData ModelContainer init
/// fails. Both are non-user-recoverable provisioning / install corruption
/// bugs. Instead of falling back to MockServices (which let the user
/// interact with a UI that didn't actually persist or block), surface
/// `FatalInitView` — a non-dismissible diagnostic screen with copy/contact
/// actions.
struct ContentView: View {
    @State private var initState: InitState

    private enum InitState {
        case ready(ContentViewModel)
        case fatal(String)
    }

    init() {
        do {
            let vm = try ContentViewModel()
            self._initState = State(wrappedValue: .ready(vm))
        } catch {
            self._initState = State(wrappedValue: .fatal("ContentViewModel init failed: \(error.localizedDescription)"))
        }
    }

    var body: some View {
        switch initState {
        case .ready(let vm):
            AuthorizedContentView(viewModel: vm)
        case .fatal(let diagnostic):
            FatalInitView(diagnostic: diagnostic)
        }
    }
}

private struct AuthorizedContentView: View {
    @State var viewModel: ContentViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !viewModel.hasInitialized {
                Color(AppConstants.Colors.background)
                    .ignoresSafeArea()
            } else if viewModel.showingSetupFlow {
                SetupFlowView(
                    setupCoordinator: viewModel.setupCoordinator,
                    onIntentionQuoteSet: { quote in
                        viewModel.setIntentionQuote(quote)
                    }
                ) {
                    Task {
                        await viewModel.completeSetupFlow()
                    }
                }
            } else {
                MainTabView(viewModel: viewModel)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let bannerError = viewModel.bannerError {
                            AppErrorBanner(
                                error: bannerError,
                                onDismiss: { viewModel.clearError() }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.bannerError != nil)
            }
        }
        .task {
            await viewModel.initializeApp()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.reconcileBlockingOnForeground() }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "intentions", url.host == "home" else { return }
            viewModel.navigateToTab(.home)
        }
    }
}

/// Main tab-based navigation when app is authorized
private struct MainTabView: View {
    let viewModel: ContentViewModel
    @State private var navigationManager = NavigationStateManager()
    @State private var settingsViewModel: SettingsViewModel?
    
    var body: some View {
        TabView(selection: Binding(
            get: { viewModel.selectedTab },
            set: { newTab in
                // Smooth tab switch only — nav reset is driven by Settings
                // lifecycle hooks (onAppear / onDisappear) below so it fires
                // deterministically with TabView's own animation rather than
                // a timer-based asyncAfter (see #48).
                viewModel.navigateToTab(newTab)
            }
        )) {
            // Home Tab - Main intention interface with Quick Actions
            HomeView(viewModel: viewModel)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
                }
                .tag(AppTab.home)

            // Settings Tab
            SettingsView(
                dataService: viewModel.dataServiceProvider,
                hasActiveSession: viewModel.activeSession != nil,
                onScheduleSettingsChanged: { schedule in
                    await viewModel.updateWeeklySchedule(schedule)
                },
                onViewModelReady: { [viewModel] vm in
                    settingsViewModel = vm
                    // Bubble Settings VM errors to the root AppErrorBanner
                    // via ContentViewModel.handleError(_:retry:) (#53).
                    vm.onError = { error, retry in
                        viewModel.handleError(error, retry: retry)
                    }
                }
            )
            .environment(navigationManager)
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
                // Reset Settings nav state at lifecycle boundaries so the pop
                // is invisible: onDisappear fires after the tab swap (user
                // can't see the reset), onAppear primes a clean root state
                // before the tab becomes visible. Replaces a 100ms
                // asyncAfter race (#48).
                .onAppear {
                    navigationManager.resetSettingsNavigationWithoutAnimation()
                    settingsViewModel?.resetSheetState()
                }
                .onDisappear {
                    navigationManager.resetSettingsNavigationWithoutAnimation()
                    settingsViewModel?.resetSheetState()
                }

        }
        .tint(AppConstants.Colors.tabBarIcon)
        // REMOVED: IntentionPromptView was legacy - intention functionality now via Quick Actions
    }
}


#Preview {
    ContentView()
}
