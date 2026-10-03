# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this is

Lodestone is a menu-bar-only macOS app: it registers as the system handler for the `magnet:` URL scheme and forwards clicked magnet links to a remote Transmission daemon over its JSON-RPC endpoint, instead of letting Safari (or any app) hand it to a local torrent client. Personal, open-source tool -- no App Store distribution planned.

**Status: working end-to-end, native app.** `Lodestone/Lodestone.xcodeproj` (SwiftUI, `MenuBarExtra` scene, no `WindowGroup`, `LSUIElement = YES`) is committed and validated against a real Transmission daemon -- clicking a magnet link in Safari routes to Lodestone, parses it, adds it via RPC, and posts a local notification. Self-signed locally with a free Apple ID team, built via Xcode or `xcodebuild` from the command line. See `README.md` for build/config details, file layout, and known gotchas.

**Test surface:** `MagnetParser`, `TransmissionConfig` and `TransmissionClient` have Swift Testing suites (`LodestoneTests`, host-less by design -- see README "Dev"). The client's RPC path (CSRF retry, status handling) is tested through an injectable `TransmissionTransport` with a scripted `MockTransport`; AppKit, Keychain and the real `URLSessionTransport` are not covered. **No open items.** The menu-bar icon is the SF Symbol `link.circle`, kept deliberately -- it began as a placeholder, but it reads well in the menu bar and the user prefers it to the brand mark in `design/icon-toolbar.svg`, so this is an intentional deviation rather than an open item. The right-click "all links show the option" Safari quirk from the old extension era no longer applies (native URL-scheme handling has no context-menu involved at all).

## Why this is a native app, not a Safari Web Extension

Lodestone was originally built as a Safari Web Extension (packaged via `xcrun safari-web-extension-packager`). It worked functionally -- click-to-add and right-click-to-add both worked -- but hit an unfixable Apple platform wall: a Safari Web Extension not distributed via the Mac App Store (an explicit, unchanged design decision -- no $99/year Developer Program) gets its "enabled" toggle reset to *off* by Safari every time Safari fully quits and relaunches, requiring a manual re-enable each time. Full diagnosis, preserved for context:

- A real, separately-fixed bug: right after archiving to `/Applications`, `pkd` (the pluginkit daemon) held a stale registration pointing at the Archive build's *transient* intermediate staging path, not the final install path -- caught via `log show` catching `sandbox_extension_issue_file_to_process failed ... No such file or directory`. Fixed by rebuilding the LaunchServices database (`lsregister -r -domain local -domain system -domain user`; the `-kill` flag some guides mention has been removed by Apple on current macOS).
- Manually checking "Allow Unsigned Extensions" (Develop menu) made the extension vanish from the Extensions list until a full Safari restart, even though it wasn't actually unsigned (real `Apple Development` signature) -- that setting doesn't apply to it and touching it made things worse, a Safari-side bug, not something fixable from the extension side.
- Even avoiding that checkbox, the core problem remained: the extension's enabled toggle reset on every Safari restart when running from `/Applications`, but not when running from Xcode's Debug build. Ruled out: provisioning profile, entitlements, Gatekeeper quarantine, stale LaunchServices registration -- all identical between the two. Eventually isolated to: the toggle only stayed persistent while **Xcode itself was running** (an ephemeral developer-session trust grant, not a persistent one) -- confirmed by testing with Xcode open vs. closed while relaunching Safari.
- The only fix Apple sanctions for this is paid Developer Program + notarization + (per Apple's own forums) still needing App Store distribution specifically to be exempt from the reset behavior -- conflicting with this project's "no App Store" design decision.

Given both remaining options (manually re-enable every Safari restart, or keep Xcode permanently open) were unacceptable, the fix was architectural: drop the Safari Web Extension model and register a plain macOS app as the default `magnet:` URL scheme handler instead (`CFBundleURLTypes`) -- Launch Services URL-scheme routing, a categorically different, much older OS mechanism with no analogous session-trust reset. The old Safari-extension source (`extension/`, the old `Lodestone Extension` App Extension target, the JS test suite) has been deleted; the magnet-parsing and Transmission RPC client logic was ported directly to Swift (`MagnetParser.swift`, `TransmissionClient.swift`) and the dark-themed popup UI became a native `SettingsView`. See README's "Gotchas" for the new architecture's own (much smaller) set of issues, mostly around App Sandbox blocking default-handler registration and App Transport Security blocking plain HTTP.

## Why this exists

Surveyed the existing landscape (as of 2026-09) before deciding to build this and found no working option:

- **`jbree/magnetic`** -- a Safari extension for exactly this purpose, but it's a legacy `.safariextz` extension from 2016. Apple removed all support for that extension format in Safari 13 (2019); it cannot load in any current Safari.
- No maintained Safari Web Extension (the current, WebExtensions-API-based format) fills this gap either -- and even a hand-built one hits the App Store distribution wall documented above.
- Chrome/Firefox have options in this space (e.g. `magnet-linker-browser-extension`, `transmitter`), and native remote-control apps exist for other purposes (`transgui`, `transmission-remote-mac`), but nothing current targets "click a magnet link in Safari, send it to a remote box" on macOS without App Store distribution.

## Design decisions

- **No App Store distribution.** Not paying Apple's $99/year Developer Program fee to distribute a free personal tool. Self-signed locally with a free Apple ID; open-source so anyone else who wants it builds and signs their own copy via Xcode.
- **Personal-scale scope.** No web UI, no settings sync, no telemetry. A single remote Transmission host + optional auth, entered once via the Settings window and stored in `UserDefaults` (host) / Keychain (auth), is the entire configuration surface.
- **Small and single-purpose.** Resist scope creep toward a general Transmission remote-control UI (that space is already served by transgui, transmission-remote-mac, etc.) -- Lodestone's entire job is "click magnet link -> add to remote host," nothing more.

## Tech stack

- **App**: SwiftUI (`MenuBarExtra` scene, `@NSApplicationDelegateAdaptor`), no Dock icon (`LSUIElement`). `AppDelegate.application(_:open:)` receives magnet: opens -- the reliable path for a `MenuBarExtra`-only app (SwiftUI's `.onOpenURL` is documented-unreliable without a `WindowGroup`).
- **URL scheme registration**: `CFBundleURLTypes` in Info.plist declares the `magnet` scheme; `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` is called on every launch to (re)claim default-handler status, since other apps (Transmission.app) can also claim it and macOS has no chooser UI for custom schemes.
- **RPC**: `URLSession` against Transmission's `/transmission/rpc` JSON-RPC endpoint (`TransmissionClient.swift`), including the `X-Transmission-Session-Id` CSRF handshake (409 response -> retry with refreshed session ID). Direct Swift port of the original JS client.

## Companion tool

[mtn-man/mintmedia](https://github.com/mtn-man/mintmedia) handles the next stage of the pipeline: managing the download -> sorted library layer. Separate concern, not merged.

## Workflow conventions

- Use `--` (double hyphen) instead of an em dash in docs, comments, and commit messages.
