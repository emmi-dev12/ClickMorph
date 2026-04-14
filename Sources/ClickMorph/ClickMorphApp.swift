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
        didSet { manager.setCursorDiameter(selectedSize.diameter) }
    }
    @Published var selectedColor: CursorColor = .white {
        didSet { manager.setCursorColor(selectedColor.nsColor) }
    }

    let manager = CursorOverlayManager()

    init() {
        manager.start()
    }

    func toggle() {
        isEnabled.toggle()
        isEnabled ? manager.enable() : manager.disable()
    }
}

// MARK: - Cursor size options

enum CursorSize: String, CaseIterable, Identifiable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var id: String { rawValue }

    var diameter: CGFloat {
        switch self {
        case .small:  return 20
        case .medium: return 28
        case .large:  return 40
        }
    }
}

// MARK: - Cursor color options

enum CursorColor: String, CaseIterable, Identifiable {
    case white  = "White"
    case yellow = "Yellow"
    case coral  = "Coral"
    case sky    = "Sky Blue"
    case mint   = "Mint"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .white:  return .white
        case .yellow: return NSColor(red: 1.0,  green: 0.92, blue: 0.23, alpha: 1)
        case .coral:  return NSColor(red: 1.0,  green: 0.45, blue: 0.40, alpha: 1)
        case .sky:    return NSColor(red: 0.40, green: 0.80, blue: 1.0,  alpha: 1)
        case .mint:   return NSColor(red: 0.40, green: 0.95, blue: 0.75, alpha: 1)
        }
    }
}

// MARK: - Menu bar UI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // Enable / Disable
        Button(appState.isEnabled ? "Disable ClickMorph" : "Enable ClickMorph") {
            appState.toggle()
        }
        .keyboardShortcut("e", modifiers: [])

        Divider()

        // Cursor size — Picker(.inline) renders native macOS radio checkmarks
        Menu("Size") {
            Picker("Size", selection: $appState.selectedSize) {
                ForEach(CursorSize.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        // Cursor color
        Menu("Color") {
            Picker("Color", selection: $appState.selectedColor) {
                ForEach(CursorColor.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Divider()

        Button("Quit ClickMorph") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [])
    }
}
