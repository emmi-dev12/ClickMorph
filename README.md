# ClickMorph

A lightweight macOS menu bar app that replaces the system cursor with an animated, customisable overlay — bigger, tinted, and satisfying to click.

- Scales to any size (Tiny → Huge)
- Shrinks on click, springs back on release
- Outward ripple ring on mouse-down
- 7 colour tints (or none)
- Adjustable animation speed
- Tracks cursor shape changes (arrow, i-beam, pointer, resize handles, etc.)
- Visible in screen recordings
- Runs silently in the menu bar — no Dock icon

**Requires macOS 13 Ventura or later.**

---

## Install from DMG (recommended)

1. Download the latest `ClickMorph-x.x.x.dmg` from [Releases](../../releases).
2. Open the DMG and drag **ClickMorph.app** into your **Applications** folder.
3. Launch ClickMorph from Applications.
4. When prompted, grant **Accessibility** permission (see below).

---

## Build from source

### Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

### One-command install

```bash
git clone https://github.com/emmi-dev12/clickmorph.git
cd clickmorph
make install
```

`make install` builds a release binary, generates the app icon, wraps everything into `ClickMorph.app`, copies it to `/Applications`, signs it ad-hoc, and launches it.

> **Why `/Applications`?** macOS ties Accessibility permission to the app's path. Installing to `/Applications` means you only grant permission once — rebuilding won't re-ask.

### Other make targets

| Command | What it does |
|---|---|
| `make build` | Compile only (fast, no bundle) |
| `make run` | Build + sign + launch from project folder (dev) |
| `make install` | Build + icon + sign + install to `/Applications` + launch |
| `make dmg VERSION=1.2.3` | Create a drag-to-install DMG |
| `make clean` | Remove build artefacts and the `.app` bundle |

---

## Accessibility permission

ClickMorph uses a **listen-only** CGEventTap to track mouse events system-wide. This requires Accessibility access.

On first launch a dialog will appear. If it doesn't:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add `ClickMorph.app`
3. Toggle it on

ClickMorph will start automatically once access is granted — no relaunch needed.

---

## Menu bar options

Click the cursor icon in the menu bar to access settings. All settings are saved and restored on relaunch.

| Setting | Description |
|---|---|
| Enable / Disable | Toggle the overlay on and off (shortcut: `E`) |
| Cursor Size | Tiny (0.8×) · Small (1.1×) · **Medium (1.6×)** · Large (2.2×) · Huge (3×) |
| Cursor Tint | None · Red · Orange · Yellow · Green · Blue · Purple · Pink |
| Click Swell | Shrink-and-spring animation on mouse-down/up |
| Click Ripple | Expanding ring on mouse-down |
| Animation Speed | Slider from 0.25× (slow) to 2.0× (fast) |
| Launch at Login | Start ClickMorph automatically when you log in |
| Auto-Update | Silently download and install new releases on launch (off by default) |
| Check for Updates… | Manually check for a newer version right now |
| Quit | Quit ClickMorph (`Q`) |

---

## How it works

ClickMorph installs a **listen-only CGEventTap** at the HID level. It never intercepts or modifies events — it only observes them, so it cannot interfere with other apps or games.

The system cursor is hidden using `CGDisplayHideCursor` plus a 1×1 transparent `NSCursor`. A full-screen transparent overlay window (at the cursor window level — above everything, including full-screen apps) hosts a `CALayer`-backed view that mirrors the real cursor's position and shape at the configured scale.

Cursor shape changes (arrow → i-beam → pointer, etc.) are detected by snapshotting `NSCursor.currentSystem` on every mouse-move event, before the transparent cursor override is applied.

The overlay window uses `sharingType = .readOnly` so it appears in screen recordings captured by tools like QuickTime, Zoom, and Focusee.

The overlay is hidden from the macOS accessibility hierarchy (`isAccessibilityElement = false`, `accessibilityHitTest` returns `nil`), so automation tools, screen readers, and remote-access apps can interact with the real UI beneath it without interference.

---

## Privacy & network activity

**ClickMorph has no telemetry, no analytics, and no crash reporting.** The only time it makes an outbound connection is for the optional update check.

### What gets sent

| Request | Triggered by | Destination | Contents |
|---|---|---|---|
| Version check | Launch with Auto-Update on, or clicking "Check for Updates…" | `api.github.com` | Nothing — a plain `GET` with no parameters or identifiers |
| DMG download | A newer version is found **and** you click "Install Now" | `github.com` | Nothing — a plain `GET` for the release asset |

Both connections are standard HTTPS GETs. There are no query parameters, no request body, and no user-specific identifiers of any kind.

The only information GitHub's servers receive is what every HTTPS request sends: your IP address and a `User-Agent` header. ClickMorph sets that header explicitly to `ClickMorph/<version> update-check` — you can see this in any packet capture.

Auto-Update is **off by default**. No connection is ever made unless you enable it or click "Check for Updates…".

### Accessibility permission

The Accessibility permission grants ClickMorph a **listen-only** `CGEventTap`. Listen-only is a macOS-enforced mode: the tap can observe cursor position and button state but cannot synthesise, forward, or modify events. No input data leaves the machine.

### Verify it yourself

**1. Read the source.**
The complete update logic is in [`Sources/ClickMorph/UpdateChecker.swift`](Sources/ClickMorph/UpdateChecker.swift), function `fetchLatestRelease()`. The entire outbound request is:

```swift
var req = URLRequest(url: URL(string: "https://api.github.com/repos/emmi-dev12/clickmorph/releases/latest")!,
                     timeoutInterval: 15)
req.setValue("application/vnd.github+json",        forHTTPHeaderField: "Accept")
req.setValue("ClickMorph/<version> update-check",  forHTTPHeaderField: "User-Agent")
// then: URLSession.shared.data(for: req)
// No body. No query params. No other headers.
```

**2. Watch live connections with `nettop`.**
`nettop` is a macOS built-in that shows real-time network activity per process. Run it while ClickMorph is open:

```bash
nettop -p $(pgrep -x ClickMorph)
```

With Auto-Update enabled, you will see one brief connection to `api.github.com:443` within the first few seconds after launch, and nothing else — ever. With Auto-Update off, the list stays empty until you manually click "Check for Updates…".

**3. Inspect HTTPS traffic with a proxy.**
[Proxyman](https://proxyman.io) (free tier) or [Charles Proxy](https://www.charlesproxy.com) act as a local HTTPS proxy and display every request an app makes, including full headers and body. After trusting the proxy certificate, you will see exactly one request to `api.github.com/repos/emmi-dev12/clickmorph/releases/latest` with an empty body and the User-Agent above. Nothing else.

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/ClickMorph.app

# Remove saved settings
defaults delete com.clickmorph.ClickMorph
```

Then remove ClickMorph from **System Settings → Privacy & Security → Accessibility**.

---

## License

MIT
