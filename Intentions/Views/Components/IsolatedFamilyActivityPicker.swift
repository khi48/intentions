import SwiftUI
import UIKit
@preconcurrency import FamilyControls

/// Isolated FamilyActivityPicker that prevents parent sheet dismissal
/// This is a workaround for iOS bug where FamilyActivityPicker dismisses parent presentation context
/// TODO: Remove this workaround when Apple fixes the underlying issue
struct IsolatedFamilyActivityPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selection: FamilyActivitySelection
    
    func makeUIViewController(context: Context) -> IsolatedPickerViewController {
        let controller = IsolatedPickerViewController()
        controller.coordinator = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: IsolatedPickerViewController, context: Context) {
        uiViewController.coordinator = context.coordinator
        
        if isPresented && !uiViewController.isPickerPresented {
            uiViewController.presentFamilyActivityPicker()
        } else if !isPresented && uiViewController.isPickerPresented {
            uiViewController.dismissFamilyActivityPicker()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: IsolatedFamilyActivityPicker
        
        init(_ parent: IsolatedFamilyActivityPicker) {
            self.parent = parent
        }
        
        @MainActor
        func pickerDidFinish(with selection: FamilyActivitySelection) {
            parent.selection = selection
            parent.isPresented = false
        }
        
        @MainActor
        func pickerDidCancel() {
            parent.isPresented = false
        }
    }
}

/// Custom UIViewController that presents FamilyActivityPicker in isolated window
class IsolatedPickerViewController: UIViewController {
    var coordinator: IsolatedFamilyActivityPicker.Coordinator?
    private var pickerWindow: UIWindow?
    var isPickerPresented: Bool { pickerWindow != nil }
    
    func presentFamilyActivityPicker() {
        guard pickerWindow == nil else { 
            print("⚠️ ISOLATED PICKER: Already presenting, ignoring duplicate request")
            return 
        }
        
        print("🎯 ISOLATED PICKER: Presenting FamilyActivityPicker")
        
        // Create isolated window
        if let windowScene = view.window?.windowScene {
            let window = UIWindow(windowScene: windowScene)
            
            // Create picker view controller
            let pickerView = IsolatedFamilyPickerView(
                onFinish: { [weak self] selection in
                    print("✅ ISOLATED PICKER: User finished with selection")
                    Task { @MainActor in
                        // Small delay to let the system clean up properly
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        self?.coordinator?.pickerDidFinish(with: selection)
                        self?.cleanupWindow()
                    }
                },
                onCancel: { [weak self] in
                    print("❌ ISOLATED PICKER: User cancelled")
                    Task { @MainActor in
                        // Small delay to let the system clean up properly
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        self?.coordinator?.pickerDidCancel()
                        self?.cleanupWindow()
                    }
                }
            )
            
            let hostingController = UIHostingController(rootView: pickerView)
            window.rootViewController = hostingController
            window.windowLevel = UIWindow.Level.alert
            window.makeKeyAndVisible()
            
            self.pickerWindow = window
        }
    }
    
    func dismissFamilyActivityPicker() {
        print("🔄 ISOLATED PICKER: Dismissing FamilyActivityPicker")
        cleanupWindow()
    }
    
    private func cleanupWindow() {
        print("🧹 ISOLATED PICKER: Cleaning up window")
        guard let window = pickerWindow else { return }
        
        // More thorough cleanup to prevent plugin connection issues
        Task { @MainActor in
            // First, hide the window
            window.isHidden = true
            window.resignKey()
            
            // Give the system time to process the resignation
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            // Then remove the root view controller
            if let rootVC = window.rootViewController {
                rootVC.view.removeFromSuperview()
                window.rootViewController = nil
            }
            
            // Finally clear our reference
            self.pickerWindow = nil
            print("✅ ISOLATED PICKER: Window cleanup completed")
        }
    }
}

/// Minimal SwiftUI view for the isolated FamilyActivityPicker
struct IsolatedFamilyPickerView: View {
    @State private var showingPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var hasInitialized = false
    @State private var isFinishing = false
    
    let onFinish: (FamilyActivitySelection) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        // Transparent container that just hosts the FamilyActivityPicker
        Color.clear
            .familyActivityPicker(
                isPresented: $showingPicker,
                selection: $selection
            )
            .onAppear {
                // Delay the picker presentation to allow proper initialization
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    await MainActor.run {
                        if !hasInitialized {
                            hasInitialized = true
                            showingPicker = true
                            print("📱 ISOLATED PICKER: Showing picker after initialization delay")
                        }
                    }
                }
            }
            .onChange(of: selection) { oldSelection, newSelection in
                // Only auto-finish if user has made a meaningful selection
                // and we're not already in the process of finishing
                guard !isFinishing else { return }
                
                let hasNewApps = !newSelection.applications.isEmpty && newSelection.applications != oldSelection.applications
                let hasNewCategories = !newSelection.categories.isEmpty && newSelection.categories != oldSelection.categories
                
                if hasNewApps || hasNewCategories {
                    print("📱 ISOLATED PICKER: Selection changed, will finish")
                    isFinishing = true
                    
                    // Add a small delay to ensure the picker UI has fully updated
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        await MainActor.run {
                            onFinish(newSelection)
                        }
                    }
                }
            }
            .onChange(of: showingPicker) { _, isShowing in
                // Handle cancellation when picker is dismissed
                if !isShowing && !isFinishing && hasInitialized {
                    print("📱 ISOLATED PICKER: Picker dismissed, will cancel")
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        await MainActor.run {
                            onCancel()
                        }
                    }
                }
            }
    }
}