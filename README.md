# Lodestone

Lodestone -- forward magnet links to a remote Transmission daemon.

(Named independently of, and unrelated to, Final Fantasy XIV's official "Lodestone" web service, which is a common search result for the name.)

## What it does

Lodestone is a Safari Web Extension. It watches for a clicked or right-clicked `magnet:` link and forwards it to a remote Transmission daemon's JSON-RPC endpoint (`/transmission/rpc`), instead of letting Safari try to hand the link to a local torrent client.

## Status / scope

Personal, open-source tool -- no App Store distribution. Self-signed locally via Xcode with a free Apple ID; anyone else who wants it builds and signs their own copy. It is deliberately small and single-purpose: click a magnet link, add it to one configured remote host, nothing more. It is not a general Transmission remote-control UI -- see `transgui` or `transmission-remote-mac` for that.

## Requirements

- macOS with Xcode installed (for the packaging step and to build/sign the app).
- Safari 16.4+ (Manifest V3 extension support).
- A reachable Transmission daemon with RPC enabled.

## Building & installing

1. Clone this repo.
2. Run Apple's packager against the `extension/` folder to generate the native app wrapper and Xcode project:
   ```
   xcrun safari-web-extension-packager extension --project-location . --bundle-identifier com.<you>.Lodestone
   ```
   Flags can drift across Xcode versions -- check `xcrun safari-web-extension-packager --help` if the above doesn't match what you have installed.
3. Open the generated `.xcodeproj`, set the signing team to your personal (free) Apple ID team, and build & run once to register the extension with Safari.
4. Enable the extension in Safari Settings > Extensions. If it's an unnotarized local build, you'll also need "Allow Unsigned Extensions" in Safari's Develop menu.

## Configuring

Open the extension's options page and enter:
- **Transmission host** (`host:port`), e.g. `192.168.1.50:9091`
- **Auth** (`user:pass`), optional, only if RPC auth is enabled on your Transmission daemon

On save, Safari will prompt for permission to reach that specific host -- this is a one-time, per-host permission (not a blanket "access all sites" grant), requested only for the host you actually configured.

## Usage

Click a magnet link, or right-click one and choose "Add magnet to Transmission." The toolbar icon shows a green "OK" or red "ERR" badge; hover it for error detail on failure.

## Development

```
extension/     -- the plain WebExtension source, fed directly into the Xcode packager
  manifest.json
  background.js
  content.js
  options.html
  options.js
  lib/
    magnet.js               -- magnet: URI parsing/validation
    transmission-client.js  -- Transmission JSON-RPC client (CSRF handshake, basic auth)
tests/         -- Node-only unit tests for extension/lib/*.js, not shipped in the extension
```

Run tests with:
```
npm test
```

No build step, no bundler, no npm dependencies for the extension itself -- `extension/` is loaded by Safari as-is.

## Known limitations / non-goals

- No general Transmission control UI -- add-only.
- No `notifications` permission -- feedback is a toolbar badge only.
- No icon set yet -- add one later with an icon design tool; the manifest omits `icons` for now.
- The badge-clear timer is best-effort: if Safari suspends the background page before the timer fires, the badge persists until the next event resets it.
- The right-click menu item ("Add magnet to Transmission") appears on every link, not just magnet ones -- Safari rejects `magnet:*` as an invalid `targetUrlPatterns` value (the WebExtensions match-pattern grammar requires a `scheme://host/path` shape, which the non-hierarchical `magnet:` scheme can't satisfy). Clicking it on a non-magnet link just produces the normal "not a magnet URI" error.

## Relationship to magnetfwd

Lodestone is a companion project to `magnetfwd`, a small Go daemon that polls the macOS clipboard for magnet links and forwards them to Transmission. magnetfwd catches magnet URIs copied as plain text; Lodestone catches magnet URIs that appear as an actual clickable link in Safari. Different trigger, same destination, same underlying protocol -- deliberately not merged (different languages, different OS integration points), but the config keys (`transmission_host` / `transmission_auth`) are named the same on purpose to keep the two projects legible as a pair.

## License

Not yet decided.
