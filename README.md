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
    TransmissionConfig.swift      -- validated host + auth (the only place either is parsed)
    TransmissionClient.swift      -- RPC client (CSRF handshake, basic auth, 10s timeout)
    Preferences.swift             -- UserDefaults (host)
    KeychainStore.swift           -- Keychain (auth credential); both read and write report failure
    NotificationFeedback.swift    -- local notification on add success/failure; reports when it can't be seen
    MenuBarMenuView.swift         -- Settings.../Quit menu
    SettingsView.swift            -- native Settings scene
    Assets.xcassets/
design/
  icon.svg + generate-icons.sh    -- app icon only; icon-toolbar.svg is historical (see script comment)
                                     and stays unused: the menu-bar icon is the SF Symbol link.circle by choice
```

## Dev

Run the tests with Cmd+U in Xcode, or:

```
xcodebuild test -project Lodestone/Lodestone.xcodeproj -scheme Lodestone -destination 'platform=macOS'
```

`LodestoneTests` covers `MagnetParser` and `TransmissionConfig`, written with Swift Testing. Two things about it are deliberate and worth knowing before you extend it:

- **The bundle has no test host.** The default Xcode template would set `TEST_HOST` to the app, which launches it to inject the tests -- and `applicationDidFinishLaunching` claims the default handler, so every test run would reassign the *system-wide* `magnet:` handler on the developer's machine. `MagnetParser.swift`, `TransmissionConfig.swift` and `TransmissionClient.swift` are direct members of the test target instead, which works because none of them touch anything beyond Foundation at parse time. A test for anything that touches AppKit, Keychain or the network will need a different arrangement.
- **The reject cases matter as much as the accept cases.** Several are links that look valid but which Transmission itself refuses; "fixing" the parser to accept them would only move the failure to the daemon.

`xcodebuild test` prints `Executed 0 tests` at the end. That is the legacy XCTest counter, which does not see Swift Testing tests -- check the result-bundle summary, or Xcode's test navigator, for real counts.

`MagnetParser.swift` is no longer a port of the old JS -- it is written against `libtransmission/magnet-metainfo.cc` (`tr_magnet_metainfo::parseMagnet`), since Lodestone forwards the URI to Transmission verbatim and so should accept exactly what Transmission accepts, no more and no less. The non-obvious parts of that contract, each annotated in the source: every query entry is scanned (not just the first `xt`), the `xt` key is matched exactly (`xt.1`/`xt.2` are *not* recognized, though `tr.1` is) and its `urn:btih:` prefix case-sensitively, the hash must be exactly 40 hex or 32 base32 characters, `xt` is compared percent-encoded while `dn`/`tr` are decoded, and a v2-only `urn:btmh:` link is rejected because upstream sets its `got_hash` flag only in the v1 branch.

`KeychainStore` uses the file-based keychain, not the data-protection keychain (`kSecUseDataProtectionKeychain`). Switching would be the more modern choice, but it is a different store: an already-saved credential would become invisible and have to be re-entered, and it depends on entitlements this app only gets from a free-Apple-ID provisioning profile. Worth revisiting deliberately, not as a drive-by.

`TransmissionConfig` is the one place the host and auth strings are interpreted. Constructing one either yields a usable `rpcURL`/`webURL`/`authHeader` or throws -- there is no fallback endpoint, deliberately: the previous code resolved an unparseable host (`::1:9091`, or anything with a space in it) to a literal host named `invalid`, which failed later as "could not reach transmission at ...", indistinguishable from a daemon that was simply down. Credentials typed into the host field are rejected rather than dropped, for the same reason. It is also where the cleartext rule lives: `http://` is accepted only for loopback, RFC 1918, CGNAT (`100.64.0.0/10`), link-local, IPv6 unique-local, `localhost`, `.local`, `.ts.net`, and unqualified single-label names -- anything routable must be `https://`, since Transmission's Basic auth header rides on every RPC request. `TransmissionClient` takes a config rather than raw strings, so it has nothing left to validate.

The RPC mechanics in `TransmissionClient.swift` are still a direct port of the old `extension/lib/transmission-client.js`; those deleted `tests/*.test.js` fixtures remain the right behavioral spec for the request/retry path if a suite gets added for it later.

## Gotchas

- **App Sandbox blocks the default-handler claim.** The self-claim-on-launch call (see AppDelegate) fails under App Sandbox -- there's no entitlement that allows a sandboxed app to mutate the system-wide Launch Services default-handler database. App Sandbox is disabled for this target (`ENABLE_APP_SANDBOX = NO`); this is fine for a non-App-Store personal tool, but re-enabling sandbox would silently break default-handler registration again. Switching from the deprecated `LSSetDefaultHandlerForURLScheme` (which reported this as OSStatus `-54`, `permErr`) to `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` changes only how the failure is reported, not the restriction. There is no user-facing fallback either: macOS has no chooser UI for custom URL schemes (see below), and Finder's Open With applies to file types, not schemes -- so a sandboxed build has no way to become the `magnet:` handler at all.
- **App Transport Security blocks plain HTTP by default.** Transmission's RPC is unencrypted `http://`, so `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` is set in Info.plist. The narrower `NSAllowsLocalNetworking` exception was considered but rejected -- it only covers RFC 1918 private ranges, not CGNAT/Tailscale-style `100.64.0.0/10` addresses, and the host is user-configured so it could be anywhere -- which also rules out an `NSExceptionDomains` list, since there is no domain to name at build time. The narrowing lives in `TransmissionConfig` instead, which refuses cleartext to anything it cannot place inside a network the user controls. ATS stays open; the app is the one enforcing the rule, and it can do so against the host as actually typed.
- **Other apps can also claim `magnet:`.** Transmission.app's own GUI client registers for the scheme too, and macOS silently picks one as default with no chooser UI for custom schemes (unlike the browser/mail picker in System Settings). Lodestone re-calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` on every launch to reclaim itself as default -- which means simply opening Lodestone (not just configuring it) changes a system-wide association. That's inelegant, and reclaiming on every launch rather than only when the user asks is a real tradeoff, but there's no alternative available: with no picker UI, the only way to guarantee Lodestone stays the handler is to keep re-asserting it, and for a personal tool whose entire purpose is being that handler, doing so automatically is the right default.
- **Local notifications default to a silent "None" alert style** for a newly-permissioned app in System Settings -- `UNUserNotificationCenter` reporting `authorizationStatus = .authorized` doesn't mean a banner will actually show; the per-app Alert Style (System Settings -> Notifications -> Lodestone) needs to be set to Banners or Alerts. The Settings window detects both this and an outright denied prompt and says so, with a link to the right pane, since notifications are the app's only output -- without that, either state leaves an app that works perfectly and appears to do nothing.

## Companion: mintmedia

[github.com/mtn-man/mintmedia](https://github.com/mtn-man/mintmedia) handles the next stage -- managing the download -> sorted library layer. Not merged; separate concern.

## License

MIT -- see [LICENSE.txt](LICENSE.txt).
