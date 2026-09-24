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
    var body: some View {
        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        Divider()
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
