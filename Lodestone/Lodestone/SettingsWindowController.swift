//
//  SettingsWindowController.swift
//  Lodestone
//
//  A plain NSWindow, not a SwiftUI Settings scene -- Settings scenes /
//  openSettings() are documented-fragile in MenuBarExtra-only apps (no
//  WindowGroup), needing hidden decoy windows and timing hacks to work
//  at all. Not worth it for a 2-field form.
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    convenience init() {
        // NSWindow(contentViewController:) doesn't reliably size/position
        // itself -- use the designated initializer with an explicit frame
        // so the window is guaranteed visible rather than possibly created
        // at zero size or off-screen.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lodestone"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
