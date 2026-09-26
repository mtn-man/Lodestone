//
//  MenuBarMenuView.swift
//  Lodestone
//
//  Deliberately minimal -- no torrent list, no history (see CLAUDE.md's
//  scope-creep guardrail: this app's entire job is "click magnet link ->
//  add to remote host," nothing more).
//

import SwiftUI

struct MenuBarMenuView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // openSettings rather than SettingsLink, which takes no action
        // closure. The activate() here is for the case SettingsView's
        // onAppear cannot cover: re-selecting this item while the window is
        // already open, where the view never appears again.
        //
        // The shortcut is declared for the affordance -- it is what draws
        // the Command-comma hint beside the item. The Settings scene also
        // registers Command-comma itself, so either handler may be the one
        // that fires; raising the window is handled in SettingsView, which
        // is common to both paths.
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        // HIG names this "Quit <App Name>", not bare "Quit". The shortcut
        // only fires while this menu is open -- an accessory app has no
        // menu bar of its own for a global Command-Q to live in.
        Button("Quit Lodestone") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
