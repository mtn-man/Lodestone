//
//  LodestoneApp.swift
//  Lodestone
//

import SwiftUI

@main
struct LodestoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Lodestone", systemImage: "link.circle") {
            MenuBarMenuView()
        }

        // A Settings scene rather than a hand-rolled NSWindowController.
        // The old README rationale ("Settings scenes are fragile in
        // MenuBarExtra-only apps, needing decoy windows and timing hacks")
        // described the situation before macOS 14, which added SettingsLink
        // for exactly this case. The scene also supplies the standard
        // window title and frame autosave, which the controller never had.
        Settings {
            SettingsView()
        }
        // Without this, the window's frame autosave can leave it holding
        // an old, taller size from a previous layout (dead space at the
        // bottom) after content shrinks. .contentSize keeps the window
        // sized to what SettingsView actually needs.
        .windowResizability(.contentSize)
    }
}
