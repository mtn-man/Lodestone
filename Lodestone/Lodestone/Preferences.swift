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
}
