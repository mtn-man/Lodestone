#!/bin/sh
# Regenerates every icon size from design/icon.svg and copies them into
# the app icon, extension icon, and status-window icon locations.
# Requires: rsvg-convert, ImageMagick (magick).
#
# Uses ImageMagick (with -type TrueColorAlpha, forcing plain RGBA output)
# rather than sips for the resize step, mainly to get consistent, known
# output -- sips's PNG color-type choice varies with image content.
#
# IMPORTANT -- avoid very-dark/near-black background colors in icon.svg.
# We hit a real, reproducible Safari bug: a background of #0d0d0f made
# Safari silently fail to load the extension's `icons`/`action.default_icon`
# manifest entries (blank toolbar icon and blank Extensions-settings icon,
# while the exact same files displayed fine in the Dock and status window).
# Isolated via branch-based bisection -- RGBA vs palette, icon sizes, and
# rotation all turned out to be irrelevant; only the background color did.
# `#141416` and `#1c3a5e` both work; `#0d0d0f` does not. Exact threshold
# unknown -- stay clearly clear of true black if you change this.
#
# IMPORTANT -- the Safari TOOLBAR icon (action.default_icon) has a real,
# separate bug from the near-black one above: a background whose color reads
# as too dark/desaturated gets auto-tinted solid blue (looked like a
# template/mask-image treatment -- with a very dark near-full-bleed square it
# still showed some glyph detail through the tint; with a dark circle at only
# ~48% coverage it went to a completely flat blue disc, no detail at all).
# It's about the COLOR's darkness, not the presence of a background shape --
# confirmed by direct A/B: a dark navy/near-black circle -> tinted; the exact
# same circle in a bright saturated color (red, then navy `#1c3a5e`) -> renders
# correctly. Exact luminance threshold unknown; stick to clearly bright/
# saturated colors for anything in the toolbar icon specifically.
#
# This also solves the "icon looks bigger than other extensions'" complaint:
# Safari trims the icon to its visible content and rescales that back up to
# fill a fixed slot, so a bare glyph with transparent padding just gets
# rescaled right back to the same apparent size (confirmed directly -- padding
# only cost resolution, never changed the on-screen footprint). A properly
# safe-colored background badge (circle) gives Safari a deliberately-sized
# trim target instead, so the whole badge -- not just the bare glyph -- is
# what gets fit to the slot, which is how real extensions (checked Bitwarden
# and uBlock Origin Lite directly) end up looking reasonably sized: their
# icon is a colored badge shape with the glyph inside it, not a bare glyph.
# design/icon-toolbar.svg is that separate badge-style source (not derived
# from icon.svg, which stays background-free-of-tint-risk since it's only
# used where the tint bug doesn't apply: Dock, Extensions pane, status window).
# After running this, rebuild in Xcode, then clear the stale icon caches:
#   touch "$APP" && lsregister -f "$APP" && killall Dock && killall Finder
#   pluginkit -r "$EXT" && pluginkit -a "$EXT"
#   fully quit and relaunch Safari
# (see the project chat history for the full commands)

set -e
cd "$(dirname "$0")/.."

SVG="design/icon.svg"
TOOLBAR_SVG="design/icon-toolbar.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rsvg-convert -w 1024 -h 1024 "$SVG" -o "$TMP/icon-1024.png"
rsvg-convert -w 1024 -h 1024 "$TOOLBAR_SVG" -o "$TMP/icon-toolbar-1024.png"

resize() {
  # $1 = size (square), $2 = output path, $3 = source (default: filled master)
  magick "${3:-$TMP/icon-1024.png}" -resize "${1}x${1}" -type TrueColorAlpha -define png:color-type=6 -strip "$2"
}

APPICON="Lodestone/Lodestone/Assets.xcassets/AppIcon.appiconset"
EXT_ICONS="extension/lib/icons"
STATUS_ICON="Lodestone/Lodestone/Resources/Icon.png"

resize 16 "$APPICON/icon_16x16.png"
resize 32 "$APPICON/icon_16x16@2x.png"
resize 32 "$APPICON/icon_32x32.png"
resize 64 "$APPICON/icon_32x32@2x.png"
resize 128 "$APPICON/icon_128x128.png"
resize 256 "$APPICON/icon_128x128@2x.png"
resize 256 "$APPICON/icon_256x256.png"
resize 512 "$APPICON/icon_256x256@2x.png"
resize 512 "$APPICON/icon_512x512.png"
magick "$TMP/icon-1024.png" -type TrueColorAlpha -define png:color-type=6 -strip "$APPICON/icon_512x512@2x.png"

# Apple's own guidance: 16/19/32/38 for the toolbar (action.default_icon),
# 48/64/96/128/256/512 for Safari's Preferences panes (icons) -- Safari
# apparently requires an exact declared size rather than scaling from the
# nearest available one, so every one of these must be present.
resize 16 "$EXT_ICONS/icon-toolbar-16.png" "$TMP/icon-toolbar-1024.png"
resize 19 "$EXT_ICONS/icon-toolbar-19.png" "$TMP/icon-toolbar-1024.png"
resize 32 "$EXT_ICONS/icon-toolbar-32.png" "$TMP/icon-toolbar-1024.png"
resize 38 "$EXT_ICONS/icon-toolbar-38.png" "$TMP/icon-toolbar-1024.png"
resize 48 "$EXT_ICONS/icon-48.png"
resize 64 "$EXT_ICONS/icon-64.png"
resize 96 "$EXT_ICONS/icon-96.png"
resize 128 "$EXT_ICONS/icon-128.png"
resize 256 "$EXT_ICONS/icon-256.png"
resize 512 "$EXT_ICONS/icon-512.png"

resize 384 "$STATUS_ICON"

echo "Icons regenerated as truecolor RGBA. Rebuild in Xcode, then clear the icon caches (see comment at top of this script)."
