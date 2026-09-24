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
    }
}
