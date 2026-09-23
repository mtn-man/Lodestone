# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this is

Lodestone is a planned Safari Web Extension: intercept a clicked (or right-clicked) `magnet:` link in Safari and forward it to a remote Transmission daemon over its JSON-RPC endpoint, instead of letting Safari try to hand it to a local torrent client. Personal, open-source tool -- no App Store distribution planned.

**Status: idea stage.** Design thinking captured below, no code or project scaffolding yet.

## Why this exists

Surveyed the existing landscape (as of 2026-09) before deciding to build this and found no working option:

- **`jbree/magnetic`** -- a Safari extension for exactly this purpose, but it's a legacy `.safariextz` extension from 2016. Apple removed all support for that extension format in Safari 13 (2019); it cannot load in any current Safari.
- No maintained Safari Web Extension (the current, WebExtensions-API-based format) fills this gap.
- Chrome/Firefox have options in this space (e.g. `magnet-linker-browser-extension`, `transmitter`), and native remote-control apps exist for other purposes (`transgui`, `transmission-remote-mac`), but nothing current targets "click a magnet link in Safari, send it to a remote box."

This is a companion project to **magnetfwd** (`~/dev/golang/magnetfwd`), a small Go daemon that polls the macOS clipboard for magnet links and forwards them to Transmission. magnetfwd catches magnet URIs copied as *plain text* (e.g. pasted from Discord/Slack with no clickable link); Lodestone catches magnet URIs that appear as an actual `<a href="magnet:...">` link clicked in Safari. Different trigger, same destination (a remote Transmission RPC endpoint), same underlying protocol. The two are deliberately not merged -- different languages, different OS integration points, no shared code -- but should stay conceptually consistent (see below).

## Design decisions carried over from magnetfwd

- **No App Store distribution.** Not paying Apple's $99/year Developer Program fee to distribute a free personal tool. Plan is to self-sign locally with a free Apple ID and open-source the code so anyone else who wants it builds and signs their own copy via Xcode.
- **Personal-scale scope.** No web UI, no settings sync, no telemetry. A single remote Transmission host + optional auth, entered once, is the entire configuration surface -- this mirrors magnetfwd's `transmission_host` / `transmission_auth` config keys, and reusing that naming in whatever config storage the extension ends up using (likely `browser.storage.local`) would keep the two projects legible as a pair.
- **Small and single-purpose.** Resist scope creep toward a general Transmission remote-control UI (that space is already served by transgui, transmission-remote-mac, etc.) -- Lodestone's entire job is "click magnet link -> add to remote host," nothing more.

## Expected tech stack (not yet started)

- **Extension logic**: HTML/CSS/JavaScript via the WebExtensions API (`manifest.json`, background script, `contextMenus` and/or a content script watching for `magnet:` links) -- the same model Chrome/Firefox extensions use, not Swift.
- **Packaging**: Safari requires the extension to ship inside a thin native macOS app container for signing/loading. Apple's `xcrun safari-web-extension-packager` generates that wrapper (and an Xcode project) from a plain JS extension folder -- expect to use the generated template as-is rather than hand-writing Swift.
- **RPC**: `fetch()` against Transmission's `/transmission/rpc` JSON-RPC endpoint, including the `X-Transmission-Session-Id` CSRF handshake (409 response -> retry with refreshed session ID) -- the same handshake magnetfwd's `internal/transmission/client.go` implements in Go; port the logic, not the code.

## Naming

**Lodestone** was chosen over MagSling, FlingMag, and MagRelay. No GitHub repo-name collisions exist in the torrent/magnet/Safari space, but "lodestone" is also the name of Final Fantasy XIV's official web service (unrelated, but a common search result) -- worth a disambiguating subtitle in the eventual README, e.g. "Lodestone -- forward magnet links to remote Transmission."

## Workflow conventions

- Use `--` (double hyphen) instead of an em dash in docs, comments, and commit messages.
