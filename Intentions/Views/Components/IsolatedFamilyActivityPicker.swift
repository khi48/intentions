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
        guard pickerWindow == nil else { return }
        
        // Create isolated window
        if let windowScene = view.window?.windowScene {
            let window = UIWindow(windowScene: windowScene)
            
            // Create picker view controller
            let pickerView = IsolatedFamilyPickerView(
                onFinish: { [weak self] selection in
                    Task { @MainActor in
                        self?.coordinator?.pickerDidFinish(with: selection)
                        self?.cleanupWindow()
                    }
                },
                onCancel: { [weak self] in
                    Task { @MainActor in
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
        cleanupWindow()
    }
    
    private func cleanupWindow() {
        pickerWindow?.isHidden = true
        pickerWindow = nil
    }
}

/// Minimal SwiftUI view for the isolated FamilyActivityPicker
struct IsolatedFamilyPickerView: View {
    @State private var showingPicker = true
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
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
                showingPicker = true
            }
            .onChange(of: selection) { _, newSelection in
                // Auto-finish when user makes a selection
                if !newSelection.applications.isEmpty || !newSelection.categories.isEmpty {
                    onFinish(newSelection)
                }
            }
            .onChange(of: showingPicker) { _, isShowing in
                // Handle cancellation when picker is dismissed
                if !isShowing {
                    onCancel()
                }
            }
    }
}