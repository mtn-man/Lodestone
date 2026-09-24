//
//  AppDelegate.swift
//  Lodestone
//
//  Receives magnet: opens handed off by Launch Services. application(_:open:)
//  is the reliable path for a MenuBarExtra-only app (no WindowGroup) --
//  SwiftUI's .onOpenURL is documented-unreliable in that configuration, and
//  registering an NSAppleEventManager handler for kAEGetURL directly would
//  suppress this delegate method from firing at all, so this is the only
//  URL-receiving hook in the app.
//

import Cocoa
import CoreServices
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationFeedback.requestAuthorization()
        claimMagnetHandler()
    }

    // Other installed apps (e.g. Transmission.app itself) can also register
    // CFBundleURLSchemes for magnet:, and macOS silently picks one as
    // default with no chooser UI for custom schemes (unlike browsers/mail,
    // which get a System Settings picker). Re-asserting on every launch
    // ensures Lodestone stays the default while it's running, rather than
    // silently losing the registration to whatever else last claimed it.
    private func claimMagnetHandler() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let status = LSSetDefaultHandlerForURLScheme("magnet" as CFString, bundleID as CFString)
        NSLog("Lodestone: LSSetDefaultHandlerForURLScheme(magnet, %@) -> %d", bundleID, status)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleMagnetURL(url)
        }
    }

    private func handleMagnetURL(_ url: URL) {
        Task {
            guard let info = try? MagnetParser.parse(url.absoluteString) else {
                NotificationFeedback.post(success: false, message: "Not a valid magnet link")
                return
            }
            let host = Preferences.transmissionHost
            let auth = KeychainStore.load()
            do {
                try await TransmissionClient.shared.addMagnet(uri: info.uri, host: host, auth: auth)
                NotificationFeedback.post(success: true, message: "")
            } catch {
                NotificationFeedback.post(success: false, message: TransmissionError.text(for: error))
            }
        }
    }
}
