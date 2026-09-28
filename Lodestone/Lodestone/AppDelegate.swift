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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationFeedback.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        claimMagnetHandler()
    }

    // Other installed apps (e.g. Transmission.app itself) can also register
    // CFBundleURLSchemes for magnet:, and macOS silently picks one as
    // default with no chooser UI for custom schemes (unlike browsers/mail,
    // which get a System Settings picker). Re-asserting on every launch
    // ensures Lodestone stays the default while it's running, rather than
    // silently losing the registration to whatever else last claimed it.
    //
    // NSWorkspace replaces LSSetDefaultHandlerForURLScheme, deprecated since
    // macOS 12. It identifies the app by bundle URL rather than bundle ID,
    // and reports failure by throwing rather than by an OSStatus -- the
    // failure worth recognizing in the log is still the sandbox one
    // (formerly -54 / permErr), since no entitlement permits a sandboxed app
    // to mutate the system-wide default-handler database (see README). This
    // is why ENABLE_APP_SANDBOX = NO in the target's build settings is
    // deliberate, not an oversight -- re-enabling it breaks this call.
    private func claimMagnetHandler() {
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL, toOpenURLsWithScheme: "magnet")
            } catch {
                NSLog("Lodestone: could not claim the magnet: scheme -- %@",
                      error.localizedDescription)
            }
        }
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
                await NotificationFeedback.post(success: false, message: "Not a valid magnet link")
                return
            }
            let config: TransmissionConfig
            do {
                config = try TransmissionConfig(
                    host: Preferences.transmissionHost, auth: KeychainStore.load() ?? "")
            } catch {
                await NotificationFeedback.post(success: false, message: error.localizedDescription)
                return
            }
            do {
                try await TransmissionClient.shared.addMagnet(uri: info.uri, config: config)
                await NotificationFeedback.post(success: true, message: "")
            } catch {
                await NotificationFeedback.post(success: false, message: error.localizedDescription)
            }
        }
    }
}
