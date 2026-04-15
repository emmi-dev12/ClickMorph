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

    // All three settings are persisted to UserDefaults so they survive relaunches.
    // didSet is NOT called during init(), so manager.set* must be called explicitly
    // in init() after restoring the saved values.

    @Published var selectedSize: CursorSize {
        didSet {
            UserDefaults.standard.set(selectedSize.rawValue, forKey: Keys.size)
            manager.setCursorScale(selectedSize.scale)
        }
    }
    @Published var showRipple: Bool {
        didSet {
            UserDefaults.standard.set(showRipple, forKey: Keys.ripple)
            manager.setRippleEnabled(showRipple)
        }
    }
    @Published var showClickSwell: Bool {
        didSet {
            UserDefaults.standard.set(showClickSwell, forKey: Keys.swell)
            manager.setClickSwellEnabled(showClickSwell)
        }
    }

    let manager = CursorOverlayManager()

    init() {
        let ud = UserDefaults.standard
        // Register factory defaults — only applied when the key has never been set.
        ud.register(defaults: [Keys.ripple: true, Keys.swell: true,
                                Keys.size: CursorSize.medium.rawValue])

        selectedSize   = CursorSize(rawValue: ud.string(forKey: Keys.size) ?? "") ?? .medium
        showRipple     = ud.bool(forKey: Keys.ripple)
        showClickSwell = ud.bool(forKey: Keys.swell)

        manager.start()
        // Apply restored values — didSet doesn't fire during init.
        manager.setCursorScale(selectedSize.scale)
        manager.setRippleEnabled(showRipple)
        manager.setClickSwellEnabled(showClickSwell)
    }

    func toggle() {
        isEnabled.toggle()
        isEnabled ? manager.enable() : manager.disable()
    }

    private enum Keys {
        static let size   = "clickmorph.size"
        static let ripple = "clickmorph.ripple"
        static let swell  = "clickmorph.swell"
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

        Toggle("Click Swell", isOn: $appState.showClickSwell)
        Toggle("Click Ripple", isOn: $appState.showRipple)

        Divider()

        Button("Quit ClickMorph") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [])
    }
}
