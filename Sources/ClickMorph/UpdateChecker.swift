import Foundation
import AppKit

// Checks the GitHub releases API for a newer version. When auto-install is
// enabled it downloads the DMG, mounts it, copies the .app bundle over the
// running copy, strips the quarantine xattr, then prompts the user to
// relaunch. A tiny shell script waits for the old PID to die before opening
// the new binary, so there is no gap in coverage.
final class UpdateChecker {

    private enum Result {
        case upToDate
        case available(version: String, dmgURL: URL?)
        case networkError
    }

    private let releasesAPI = URL(string: "https://api.github.com/repos/emmi-dev12/clickmorph/releases/latest")!

    // MARK: - Public entry points

    /// Silent background check — no UI unless a newer version with a DMG
    /// asset is found and autoInstall is true.
    func check(autoInstall: Bool) async {
        switch await fetchLatestRelease() {
        case .upToDate, .networkError:
            return
        case let .available(version, dmgURL):
            guard autoInstall, let dmgURL else { return }
            await downloadAndInstall(dmgURL: dmgURL, version: version)
        }
    }

    /// Manual check — always shows a result dialog.
    func checkManually() async {
        switch await fetchLatestRelease() {
        case .upToDate:
            await MainActor.run { showUpToDateAlert() }
        case .networkError:
            await MainActor.run { showNetworkErrorAlert() }
        case let .available(version, dmgURL):
            await MainActor.run { presentAvailableUpdate(version: version, dmgURL: dmgURL) }
        }
    }

    // MARK: - GitHub API

    private struct GHRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private func fetchLatestRelease() async -> Result {
        var req = URLRequest(url: releasesAPI, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(GHRelease.self, from: data)
        else { return .networkError }

        let latest  = release.tagName.drop(while: { $0 == "v" }).description
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard isNewer(latest, than: current) else { return .upToDate }

        let dmgURL = release.assets
            .first { $0.name.lowercased().hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadUrl) }
        return .available(version: latest, dmgURL: dmgURL)
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Download & install

    private func downloadAndInstall(dmgURL: URL, version: String) async {
        guard let (tmp, _) = try? await URLSession.shared.download(from: dmgURL) else {
            await MainActor.run { showDownloadFailedAlert(version: version) }
            return
        }

        // hdiutil identifies format from the extension, not the MIME type.
        let dmg = tmp.deletingLastPathComponent()
            .appendingPathComponent("ClickMorph-\(version).dmg")
        try? FileManager.default.moveItem(at: tmp, to: dmg)
        defer { try? FileManager.default.removeItem(at: dmg) }

        guard let mountPoint = mountDMG(at: dmg) else {
            await MainActor.run { showDownloadFailedAlert(version: version) }
            return
        }
        defer { _ = shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force", "-quiet"]) }

        let src  = URL(fileURLWithPath: mountPoint).appendingPathComponent("ClickMorph.app")
        let dest = Bundle.main.bundleURL

        guard FileManager.default.fileExists(atPath: src.path) else {
            await MainActor.run { showDownloadFailedAlert(version: version) }
            return
        }

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            // Remove quarantine so Gatekeeper doesn't prompt on the relaunched binary.
            _ = shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
        } catch {
            await MainActor.run { showDownloadFailedAlert(version: version) }
            return
        }

        await MainActor.run { promptRelaunch(version: version) }
    }

    // MARK: - Shell helpers

    private func mountDMG(at url: URL) -> String? {
        // -plist gives structured output; parse mount-point from system-entities.
        let out = shell("/usr/bin/hdiutil", [
            "attach", url.path, "-nobrowse", "-noverify", "-noautoopen", "-plist"
        ])
        guard let data = out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    @discardableResult
    private func shell(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL  = URL(fileURLWithPath: exe)
        p.arguments      = args
        let pipe         = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Alerts (must run on main thread)

    @MainActor
    private func presentAvailableUpdate(version: String, dmgURL: URL?) {
        let alert = NSAlert()
        alert.messageText     = "ClickMorph v\(version) Available"
        alert.informativeText = "A new version of ClickMorph is ready to download."
        if dmgURL != nil { alert.addButton(withTitle: "Install Now") }
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")

        let resp = alert.runModal()
        // Button order: [Install Now (if dmg)] [View Release] [Later]
        let installTapped = dmgURL != nil && resp == .alertFirstButtonReturn
        let viewTapped    = resp == (dmgURL != nil ? .alertSecondButtonReturn : .alertFirstButtonReturn)

        if installTapped, let dmgURL {
            Task { await self.downloadAndInstall(dmgURL: dmgURL, version: version) }
        } else if viewTapped {
            openReleasesPage()
        }
    }

    @MainActor
    private func promptRelaunch(version: String) {
        let alert = NSAlert()
        alert.messageText     = "ClickMorph Updated to v\(version)"
        alert.informativeText = "The update is installed. Relaunch ClickMorph to use the new version."
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    @MainActor
    private func showUpToDateAlert() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText     = "ClickMorph is Up to Date"
        alert.informativeText = "You're running v\(v), which is the latest version."
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    @MainActor
    private func showNetworkErrorAlert() {
        let alert = NSAlert()
        alert.messageText     = "Update Check Failed"
        alert.informativeText = "Could not reach the update server. Check your internet connection and try again."
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    @MainActor
    private func showDownloadFailedAlert(version: String) {
        let alert = NSAlert()
        alert.messageText     = "Update Download Failed"
        alert.informativeText = "Could not download ClickMorph v\(version). You can install it manually from the releases page."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { openReleasesPage() }
    }

    @MainActor
    private func openReleasesPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/emmi-dev12/clickmorph/releases/latest")!)
    }

    // MARK: - Relaunch

    // Writes a tiny shell script that polls until the old PID exits, then
    // opens the updated bundle. Running it detached and then terminating
    // the current process guarantees no gap between old and new instances.
    @MainActor
    private func relaunch() {
        let pid  = ProcessInfo.processInfo.processIdentifier
        let dest = Bundle.main.bundleURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            #!/bin/bash
            while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.05; done
            open "\(dest)"
            """
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clickmorph_relaunch.sh")
        guard (try? script.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments     = [scriptURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
