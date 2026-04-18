import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

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

    // All settings are persisted to UserDefaults so they survive relaunches.
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
    @Published var selectedTint: CursorTint? {
        didSet {
            UserDefaults.standard.set(selectedTint?.rawValue, forKey: Keys.tint)
            manager.setTintColor(selectedTint?.color)
        }
    }
    @Published var selectedShape: CursorShape {
        didSet {
            UserDefaults.standard.set(selectedShape.rawValue, forKey: Keys.shape)
            manager.setCustomShape(selectedShape, customImagePath: customImagePath)
        }
    }
    @Published var customImagePath: String? {
        didSet {
            UserDefaults.standard.set(customImagePath, forKey: Keys.customImage)
            if selectedShape == .custom {
                manager.setCustomShape(selectedShape, customImagePath: customImagePath)
            }
        }
    }
    @Published var animationSpeed: Double {
        didSet {
            UserDefaults.standard.set(animationSpeed, forKey: Keys.speed)
            manager.setAnimationSpeed(animationSpeed)
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently revert the toggle if the service call fails
                launchAtLogin = !launchAtLogin
            }
        }
    }

    let manager = CursorOverlayManager()

    init() {
        let ud = UserDefaults.standard
        // Register factory defaults — only applied when the key has never been set.
        ud.register(defaults: [
            Keys.ripple: true,
            Keys.swell:  true,
            Keys.size:   CursorSize.medium.rawValue,
            Keys.speed:  1.0,
            Keys.shape:  CursorShape.system.rawValue
        ])

        selectedSize   = CursorSize(rawValue: ud.string(forKey: Keys.size) ?? "") ?? .medium
        showRipple     = ud.bool(forKey: Keys.ripple)
        showClickSwell = ud.bool(forKey: Keys.swell)
        animationSpeed = ud.double(forKey: Keys.speed)
        selectedShape  = CursorShape(rawValue: ud.string(forKey: Keys.shape) ?? "") ?? .system
        customImagePath = ud.string(forKey: Keys.customImage)

        if let tintRaw = ud.string(forKey: Keys.tint) {
            selectedTint = CursorTint(rawValue: tintRaw)
        } else {
            selectedTint = nil
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled

        manager.start()
        // Apply restored values — didSet doesn't fire during init.
        manager.setCursorScale(selectedSize.scale)
        manager.setRippleEnabled(showRipple)
        manager.setClickSwellEnabled(showClickSwell)
        manager.setTintColor(selectedTint?.color)
        manager.setCustomShape(selectedShape, customImagePath: customImagePath)
        manager.setAnimationSpeed(animationSpeed)
    }

    func toggle() {
        isEnabled.toggle()
        isEnabled ? manager.enable() : manager.disable()
    }

    private enum Keys {
        static let size        = "clickmorph.size"
        static let ripple      = "clickmorph.ripple"
        static let swell       = "clickmorph.swell"
        static let tint        = "clickmorph.tint"
        static let speed       = "clickmorph.speed"
        static let shape       = "clickmorph.shape"
        static let customImage = "clickmorph.customImage"
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

// MARK: - Cursor shape options

enum CursorShape: String, CaseIterable, Identifiable {
    case system   = "System"
    case dot      = "Dot"
    case triangle = "Triangle"
    case custom   = "Custom Image"

    var id: String { rawValue }
}

// MARK: - Cursor tint options

enum CursorTint: String, CaseIterable, Identifiable {
    case red    = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green  = "Green"
    case blue   = "Blue"
    case purple = "Purple"
    case pink   = "Pink"

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .red:    return NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1)
        case .orange: return NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        case .yellow: return NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1)
        case .green:  return NSColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 1)
        case .blue:   return NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)
        case .purple: return NSColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1)
        case .pink:   return NSColor(red: 1.0, green: 0.3, blue: 0.7, alpha: 1)
        }
    }
}

// MARK: - Menu bar UI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    private func selectCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            appState.customImagePath = url.path
        }
    }

    var body: some View {
        Button(appState.isEnabled ? "Disable ClickMorph" : "Enable ClickMorph") {
            appState.toggle()
        }
        .keyboardShortcut("e", modifiers: [])

        Divider()

        Menu("Cursor Shape") {
            Picker("Shape", selection: $appState.selectedShape) {
                ForEach(CursorShape.allCases) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if appState.selectedShape == .custom {
                Divider()
                Button("Choose Image...") {
                    selectCustomImage()
                }
                if let imagePath = appState.customImagePath {
                    Text(URL(fileURLWithPath: imagePath).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }

        Menu("Cursor Size") {
            Picker("Cursor Size", selection: $appState.selectedSize) {
                ForEach(CursorSize.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Menu("Cursor Tint") {
            Button("None") { appState.selectedTint = nil }
            if appState.selectedTint == nil {
                // Visual indicator — checked state for "None"
                // (Button doesn't support checkmarks natively; use a label trick)
            }
            Divider()
            Picker("Tint", selection: Binding(
                get: { appState.selectedTint ?? .red },
                set: { appState.selectedTint = $0 }
            )) {
                ForEach(CursorTint.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(appState.selectedTint == nil)
        }

        Toggle("Click Swell", isOn: $appState.showClickSwell)
        Toggle("Click Ripple", isOn: $appState.showRipple)

        Divider()

        // Animation speed — slider from 0.25× (slow) to 2.0× (fast)
        VStack(alignment: .leading, spacing: 2) {
            Text("Animation Speed")
                .font(.system(size: 13))
                .padding(.horizontal, 14)
            HStack(spacing: 6) {
                Image(systemName: "tortoise")
                    .font(.system(size: 11))
                Slider(value: $appState.animationSpeed, in: 0.25...2.0, step: 0.05)
                    .frame(width: 140)
                Image(systemName: "hare")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 4)

        Divider()

        Toggle("Launch at Login", isOn: $appState.launchAtLogin)

        Divider()

        Button("Quit ClickMorph") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [])
    }
}
