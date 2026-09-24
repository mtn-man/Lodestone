//
//  NotificationFeedback.swift
//  Lodestone
//
//  Local notification feedback after each add-magnet attempt -- chosen
//  over a transient status-item flash since the user has typically
//  alt-tabbed back to Safari after clicking the link.
//
//  That choice has one failure mode worth guarding: notifications are the
//  app's only output, so if the user denies the permission prompt the app
//  goes permanently silent while still working. Nothing about a silent
//  menu-bar app suggests "check System Settings," so the denied state is
//  reported in the Settings window instead of being left to be inferred.
//

import AppKit
import Foundation
import UserNotifications

/// Without a delegate, `willPresent` defaults to suppressing a banner while
/// the app is frontmost -- reasonable for an app you are looking at, wrong
/// for this one, whose window tells you nothing about an add in flight. The
/// reachable case is narrow (the Settings window is open, so Lodestone is
/// active, and a magnet arrives) but the suppressed banner is the only
/// report that add ever makes.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

enum NotificationFeedback {
    // Fetched per use rather than held in a static. UNUserNotificationCenter
    // is not Sendable, so a stored instance is a non-Sendable value escaping
    // the main actor every time an async context touches it -- an error in
    // Swift 6 language mode. current() is a cheap accessor for a singleton.
    private static let presenter = NotificationPresenter()

    /// One-shot authorization request, awaited by every post.
    ///
    /// Without the await, the first magnet after install races the
    /// permission prompt and loses: the RPC add finishes in milliseconds
    /// while the prompt waits on a human, and `add` under `.notDetermined`
    /// neither queues nor prompts -- it just doesn't deliver. The torrent
    /// is added and the confirmation is dropped, on the one run where the
    /// user has no reason yet to trust that it worked.
    private static let authorization = Task<Bool, Never> {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    /// Installs the presentation delegate and starts the authorization
    /// request. Called from `applicationWillFinishLaunching`: the delegate
    /// has to be in place before launching finishes, and starting the
    /// request there gives it a head start on a magnet that launched the app.
    static func start() {
        UNUserNotificationCenter.current().delegate = presenter
        _ = authorization
    }

    static func post(success: Bool, message: String) async {
        guard await authorization.value else {
            NSLog("Lodestone: notifications not authorized, dropping feedback: %@",
                  success ? "added magnet" : message)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Lodestone"
        content.body = success ? "Added magnet to Transmission" : message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NSLog("Lodestone: failed to post notification: %@", String(describing: error))
        }
    }

    /// nil when feedback will be delivered. Otherwise a sentence for the
    /// Settings window explaining why it won't be.
    static func unavailableReason() async -> String? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return "Notifications are turned off, so magnets are added silently."
        case .authorized, .provisional, .ephemeral:
            // Granting permission is not enough: macOS gives a newly
            // permissioned app an alert style of None, which delivers to
            // Notification Centre and shows nothing. That is the default,
            // so it is the likeliest reason a working app looks dead.
            return settings.alertStyle == .none
                ? "Notification style is set to None, so magnets are added without a visible alert."
                : nil
        case .notDetermined:
            // The prompt has not been answered yet; not a problem to report.
            return nil
        @unknown default:
            return nil
        }
    }

    /// Pane identifier verified against
    /// /System/Library/ExtensionKit/Extensions/NotificationsSettings.appex
    /// -- System Settings panes are ExtensionKit bundles since macOS 13,
    /// and the old com.apple.preference.notifications prefPane id no longer
    /// resolves.
    static func openNotificationSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
