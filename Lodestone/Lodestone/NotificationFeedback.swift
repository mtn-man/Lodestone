//
//  NotificationFeedback.swift
//  Lodestone
//
//  Local notification feedback after each add-magnet attempt -- chosen
//  over a transient status-item flash since the user has typically
//  alt-tabbed back to Safari after clicking the link.
//

import Foundation
import UserNotifications

enum NotificationFeedback {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(success: Bool, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Lodestone"
        content.body = success ? "Added magnet to Transmission" : message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Lodestone: failed to post notification: %@", String(describing: error))
            }
        }
    }
}
