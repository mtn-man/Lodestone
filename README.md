# Lodestone

Menu-bar-only macOS app: registers as the system handler for `magnet:` links and forwards them to a remote Transmission daemon's JSON-RPC endpoint (`/transmission/rpc`).

Personal tool, no App Store distribution -- self-signed locally via a free Apple ID. Add-only; not a Transmission control UI.

## Requirements

- macOS + Xcode
- Reachable Transmission daemon with RPC enabled

## Build

Open `Lodestone/Lodestone.xcodeproj` in Xcode, confirm the signing team on the `Lodestone` target is set to your free-tier team, signing certificate **Development** (not "Sign to Run Locally" -- ad-hoc signing breaks local network access). Cmd+R to build and run -- a small icon appears in the menu bar, no Dock icon. Command-line builds also work: `xcodebuild -project Lodestone/Lodestone.xcodeproj -scheme Lodestone -configuration Debug build`.

First launch registers Lodestone as the default `magnet:` URL handler automatically (re-asserted on every launch, since other installed apps -- e.g. Transmission.app itself -- can also claim the scheme and there's no System Settings picker for custom URL schemes the way there is for browsers/mail).

## Configure

Click the menu-bar icon -> Settings...: `transmission_host` (`host:port`), optional `transmission_auth` (`user:pass`, stored in the macOS Keychain). Save runs a live RPC connectivity check -- an unreachable host or bad auth is rejected with an error instead of being saved silently. Once a host is saved, the Settings window also shows a link to Transmission's own web portal (`http://<host>/transmission/web/`).

## Layout

```
Lodestone/
  Lodestone.xcodeproj/
  Lodestone/
    LodestoneApp.swift            -- @main SwiftUI App, MenuBarExtra scene
    AppDelegate.swift             -- receives magnet: opens, claims default handler
    MagnetParser.swift            -- magnet: URI parsing/validation
    TransmissionClient.swift      -- RPC client (CSRF handshake, basic auth, 10s timeout)
    Preferences.swift             -- UserDefaults (host)
    KeychainStore.swift           -- Keychain (auth credential)
    NotificationFeedback.swift    -- local notification on add success/failure
    MenuBarMenuView.swift         -- Settings.../Quit menu
    SettingsWindowController.swift / SettingsView.swift -- native settings window
    Assets.xcassets/
design/
  icon.svg + generate-icons.sh    -- app icon only; icon-toolbar.svg is historical (see script comment)
```

## Dev

No automated test suite yet -- the original Safari-extension-era JS tests (`tests/*.test.js`, covering magnet parsing and the Transmission RPC client) were deleted along with `extension/` when this became a native app; their fixtures/cases are still the right behavioral spec if a Swift XCTest suite gets added later (`MagnetParser.swift` and `TransmissionClient.swift` are direct ports of that JS logic).

## Gotchas

- **App Sandbox blocks `LSSetDefaultHandlerForURLScheme`.** The self-claim-on-launch call (see AppDelegate) returns `-54` (`permErr`) under App Sandbox -- there's no entitlement that allows a sandboxed app to mutate the system-wide Launch Services default-handler database. App Sandbox is disabled for this target (`ENABLE_APP_SANDBOX = NO`); this is fine for a non-App-Store personal tool, but re-enabling sandbox would silently break default-handler registration again.
- **App Transport Security blocks plain HTTP by default.** Transmission's RPC is unencrypted `http://`, so `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` is set in Info.plist. The narrower `NSAllowsLocalNetworking` exception was considered but rejected -- it only covers RFC 1918 private ranges, not CGNAT/Tailscale-style `100.64.0.0/10` addresses, and the host is user-configured so it could be anywhere.
- **Other apps can also claim `magnet:`.** Transmission.app's own GUI client registers for the scheme too, and macOS silently picks one as default with no chooser UI for custom schemes (unlike the browser/mail picker in System Settings). Lodestone re-calls `LSSetDefaultHandlerForURLScheme` on every launch to reclaim itself as default.
- **`NSWindow(contentViewController:)` doesn't reliably size/position itself** -- the Settings window uses the designated `NSWindow(contentRect:styleMask:backing:defer:)` initializer with an explicit frame instead, or it can end up created off-screen/zero-size with no visible error.
- **`NSApp.delegate as? AppDelegate` is not a reliable way to reach the app delegate from a `MenuBarExtra` view** -- observed as a silent no-op (the cast apparently failing) rather than a crash. `SettingsWindowController` is a plain singleton instead, referenced directly.
- **SwiftUI's `Settings` scene / `openSettings()` is fragile in `MenuBarExtra`-only apps** (no `WindowGroup`) -- needs hidden decoy windows and timing hacks to work at all in that configuration. Settings is a plain `NSWindowController`-managed `NSWindow` instead.
- **Local notifications default to a silent "None" alert style** for a newly-permissioned app in System Settings -- `UNUserNotificationCenter` reporting `authorizationStatus = .authorized` doesn't mean a banner will actually show; the per-app Alert Style (System Settings -> Notifications -> Lodestone) needs to be set to Banners or Alerts.

## Companion: mintmedia

[github.com/mtn-man/mintmedia](https://github.com/mtn-man/mintmedia) handles the next stage -- managing the download -> sorted library layer. Not merged; separate concern.

## License

MIT -- see [LICENSE.txt](LICENSE.txt).
