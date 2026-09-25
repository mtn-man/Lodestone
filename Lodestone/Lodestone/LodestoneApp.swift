//
//  LodestoneApp.swift
//  Lodestone
//

import SwiftUI

@main
struct LodestoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // .window rather than the default .menu style: it hosts the content
        // in a real, disposable SwiftUI window that is shown and torn down
        // on every open, so .task/.onAppear genuinely rerun each time (see
        // MenuBarMenuView's connection check). .menu style keeps its
        // content view alive across opens -- state set after the first open
        // never refreshes -- and reaching into the private NSMenu that
        // backs it to work around that (reassigning its NSMenuDelegate)
        // destabilized the status item's menu-tracking loop badly enough to
        // hang the app (crash trace bottomed out in mach_msg2_trap).
        MenuBarExtra("Lodestone", systemImage: "link.circle") {
            MenuBarMenuView()
        }
        .menuBarExtraStyle(.window)

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
