# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this is

Lodestone is a Safari Web Extension: intercept a clicked (or right-clicked) `magnet:` link in Safari and forward it to a remote Transmission daemon over its JSON-RPC endpoint, instead of letting Safari try to hand it to a local torrent client. Personal, open-source tool -- no App Store distribution planned.

**Status: packaged, signed, and running persistently in Safari.** The `extension/` source (manifest, background/content scripts, settings popup, Transmission RPC client, magnet-link validation, Node unit tests) is committed and validated end-to-end against a real Transmission daemon -- click-to-add and right-click-to-add both work. It's been run through `xcrun safari-web-extension-packager`, producing `Lodestone/Lodestone.xcodeproj` (also committed, so others can build their own copy), built and self-signed locally with a free Apple ID team. See `README.md` for build/install/usage details, file layout, and known gotchas.

**Open items:** currently runs from Xcode's Debug build (DerivedData), not a permanent `/Applications` install (would need Product > Archive); the right-click context menu shows on all links, not just magnet ones (documented Safari limitation, see README).

## Why this exists

Surveyed the existing landscape (as of 2026-09) before deciding to build this and found no working option:

- **`jbree/magnetic`** -- a Safari extension for exactly this purpose, but it's a legacy `.safariextz` extension from 2016. Apple removed all support for that extension format in Safari 13 (2019); it cannot load in any current Safari.
- No maintained Safari Web Extension (the current, WebExtensions-API-based format) fills this gap.
- Chrome/Firefox have options in this space (e.g. `magnet-linker-browser-extension`, `transmitter`), and native remote-control apps exist for other purposes (`transgui`, `transmission-remote-mac`), but nothing current targets "click a magnet link in Safari, send it to a remote box."

## Design decisions

- **No App Store distribution.** Not paying Apple's $99/year Developer Program fee to distribute a free personal tool. Self-signed locally with a free Apple ID; open-source so anyone else who wants it builds and signs their own copy via Xcode.
- **Personal-scale scope.** No web UI, no settings sync, no telemetry. A single remote Transmission host + optional auth, entered once via the toolbar popup and stored in `browser.storage.local` under `transmission_host` / `transmission_auth`, is the entire configuration surface.
- **Small and single-purpose.** Resist scope creep toward a general Transmission remote-control UI (that space is already served by transgui, transmission-remote-mac, etc.) -- Lodestone's entire job is "click magnet link -> add to remote host," nothing more.

## Tech stack

- **Extension logic**: HTML/CSS/JavaScript via the WebExtensions API (`extension/manifest.json`, `background.js`, `content.js`, `contextMenus` plus a content script watching for `magnet:` links) -- the same model Chrome/Firefox extensions use, not Swift. Implemented in `extension/`.
- **Packaging**: Safari requires the extension to ship inside a thin native macOS app container for signing/loading. Apple's `xcrun safari-web-extension-packager` generates that wrapper (and an Xcode project) from the plain JS extension folder -- the generated `Lodestone/` project is used as-is rather than hand-writing Swift.
- **RPC**: `fetch()` against Transmission's `/transmission/rpc` JSON-RPC endpoint (`extension/lib/transmission-client.js`), including the `X-Transmission-Session-Id` CSRF handshake (409 response -> retry with refreshed session ID).

## Companion tool

[mtn-man/mintmedia](https://github.com/mtn-man/mintmedia) handles the next stage of the pipeline: managing the download -> sorted library layer. Separate concern, not merged.

## Workflow conventions

- Use `--` (double hyphen) instead of an em dash in docs, comments, and commit messages.
