# Lodestone

Safari Web Extension: forwards clicked/right-clicked `magnet:` links to a remote Transmission daemon's JSON-RPC endpoint (`/transmission/rpc`).

Personal tool, no App Store distribution -- self-signed locally via a free Apple ID. Add-only; not a Transmission control UI.

## Requirements

- macOS + Xcode (packaging/signing)
- Safari 16.4+ (Manifest V3)
- Reachable Transmission daemon with RPC enabled

## Build

```
xcrun safari-web-extension-packager extension --project-location . --bundle-identifier com.<you>.Lodestone
```

Open the generated `Lodestone.xcodeproj`, set the signing team on **both** targets (app + extension) to the same free-tier team, signing certificate **Development** (not "Sign to Run Locally" -- ad-hoc signing breaks local network access). Build & run to register with Safari, then enable it in Safari Settings > Extensions. Unnotarized local build also needs "Allow Unsigned Extensions" in the Develop menu.

For quick iteration without Xcode: Safari Settings > Developer > Add Temporary Extension -> point at `extension/`. Session-only, no signing.

## Configure

Toolbar popup (click the Lodestone icon): `transmission_host` (`host:port`), optional `transmission_auth` (`user:pass`). Save triggers a one-time per-host permission prompt (dynamic `optional_host_permissions`, not a blanket grant), then a live RPC connectivity check -- an unreachable host or bad auth is rejected with an error instead of being saved silently. Once a host is saved, the popup also shows a link to Transmission's own web portal (`http://<host>/transmission/web/`).

## Layout

```
extension/
  manifest.json
  background.js            -- message/contextMenu routing, badge feedback
  content.js               -- intercepts magnet: link clicks
  popup.html / popup.js    -- toolbar popup: settings form
  lib/
    magnet.js              -- magnet: URI parsing/validation
    transmission-client.js -- RPC client (CSRF handshake, basic auth, 10s timeout)
    icons/
tests/                     -- node --test coverage for lib/*.js
design/
  icon.svg + generate-icons.sh
Lodestone/                 -- generated Xcode project (packager output; committed so others can build)
```

## Dev

```
npm test
```

No build step, no bundler, no deps for the extension itself -- `extension/` loads as-is.

## Gotchas

- `contextMenus.create({targetUrlPatterns: ['magnet:*']})` is rejected -- match-pattern grammar requires `scheme://host/path`, which `magnet:` (no host) can't satisfy. Context menu item shows on all links; click-through still validates and errors cleanly on non-magnet links.
- `permissions.request()` must run synchronously off the triggering event (no `await` before it) or Safari silently drops the user-gesture association and never prompts.
- Match patterns can't encode a port -- host permission is granted per-hostname, `fetch()` still uses the real host:port.
- Icon background can't be near-black: `#0d0d0f` makes Safari silently fail to load `icons`/`action.default_icon` (blank toolbar + Extensions-pane icon, everywhere else fine); `#141416` works. No known root cause, just avoid true-black-ish values.
- The toolbar icon (`action.default_icon`) auto-tints solid blue if its background color is too dark/desaturated (a near-black or navy-dark fill, at any coverage down to ~48%) -- it's about color darkness, not the presence of a background shape. Bright/saturated colors (red, navy `#1c3a5e`) render correctly. `design/icon-toolbar.svg` is a separate source used only here.
- The toolbar icon's apparent size follows its background badge, not the bare glyph -- Safari trims to visible content and rescales to a fixed slot, so a transparent-background glyph with padding just gets rescaled back to the same size (padding is undone, only costs resolution). Give it a safely-colored background shape (a circle, like real extensions use) to control the actual on-screen footprint instead.
- No `notifications` permission -- feedback is a toolbar badge (green OK / red ERR, tooltip has error detail).
- App/plugin icon caches (LaunchServices, `pluginkit`, Safari's own extension state) are independent and go stale separately -- if an icon change doesn't show up, don't assume it's a real bug before re-registering/restarting each layer.

## Companion: mintmedia

[github.com/mtn-man/mintmedia](https://github.com/mtn-man/mintmedia) handles the next stage -- managing the download -> sorted library layer. Not merged; separate concern.

## License

MIT -- see [LICENSE.txt](LICENSE.txt).
