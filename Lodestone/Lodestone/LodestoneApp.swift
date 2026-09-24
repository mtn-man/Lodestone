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
    }
}
