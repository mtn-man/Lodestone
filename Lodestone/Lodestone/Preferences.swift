//
//  Preferences.swift
//  Lodestone
//

import Foundation

enum Preferences {
    private static let hostKey = "transmission_host"

    static var transmissionHost: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    /// Transmission's own web portal for the saved host, or nil when no
    /// host is configured or it no longer parses. Resolved on demand rather
    /// than stored, so it always points at the current server.
    ///
    /// Auth is deliberately empty: the portal asks for credentials itself,
    /// and they have no place in a URL handed to a browser.
    static var transmissionWebURL: URL? {
        try? TransmissionConfig(host: transmissionHost, auth: "").webURL
    }
}
