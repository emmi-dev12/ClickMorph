import SwiftUI
import AppKit

// MARK: - Entry point

@main
struct ClickMorphApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("ClickMorph", systemImage: "cursorarrow.rays") {
            MenuBarContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - App state

final class AppState: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published var selectedSize: CursorSize = .medium {
        didSet { manager.setCursorScale(selectedSize.scale) }
    }
    @Published var showRipple: Bool = true {
        didSet { manager.setRippleEnabled(showRipple) }
    }

    let manager = CursorOverlayManager()

    init() {
        manager.start()
        manager.setCursorScale(selectedSize.scale)
    }

    func toggle() {
        isEnabled.toggle()
        isEnabled ? manager.enable() : manager.disable()
    }
}

// MARK: - Cursor size options

enum CursorSize: String, CaseIterable, Identifiable {
    case tiny   = "Tiny"
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"
    case huge   = "Huge"

    var id: String { rawValue }

    /// Multiplier applied to the system cursor's native size.
    var scale: CGFloat {
        switch self {
        case .tiny:   return 0.8
        case .small:  return 1.1
        case .medium: return 1.6
        case .large:  return 2.2
        case .huge:   return 3.0
        }
    }
}

// MARK: - Menu bar UI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button(appState.isEnabled ? "Disable ClickMorph" : "Enable ClickMorph") {
            appState.toggle()
        }
        .keyboardShortcut("e", modifiers: [])

        Divider()

        Menu("Cursor Size") {
            Picker("Cursor Size", selection: $appState.selectedSize) {
                ForEach(CursorSize.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Toggle("Click Ripple", isOn: $appState.showRipple)

        Divider()

        Button("Quit ClickMorph") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [])
    }
}
