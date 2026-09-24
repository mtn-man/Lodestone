//
//  SettingsView.swift
//  Lodestone
//
//  Native reproduction of the old extension/popup.html dark theme and
//  save flow (validate locally -> test connectivity live -> persist only
//  on success -> show a link to Transmission's own web portal). No
//  WebExtensions permission-request step exists here -- a native app has
//  no per-origin permission model to negotiate, unlike the old popup.
//

import SwiftUI

struct SettingsView: View {
    @State private var host: String = Preferences.transmissionHost
    @State private var auth: String
    @State private var status: String
    @State private var isError: Bool
    /// The web-portal URL for the currently persisted host, or nil if none
    /// is configured. Derived from the saved host rather than tracked as a
    /// second copy of it, so the link is shown exactly when it resolves.
    @State private var savedWebURL: URL? = SettingsView.persistedWebURL()

    init() {
        // A failed keychain read must not present as "no credential set":
        // the field would come up blank and the obvious reading is that it
        // was never configured, which sends the user to the wrong problem.
        do {
            _auth = State(initialValue: try KeychainStore.load() ?? "")
            _status = State(initialValue: "")
            _isError = State(initialValue: false)
        } catch {
            _auth = State(initialValue: "")
            _status = State(initialValue: TransmissionError.text(for: error))
            _isError = State(initialValue: true)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Lodestone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: 0xF2F3F5))

            Text("Forward clicked magnet links to a remote Transmission instance.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x8C9096))
                .multilineTextAlignment(.center)

            field(label: "Transmission host (host:port)", placeholder: "192.168.1.50:9091", text: $host)
            field(label: "Authentication (user:pass, optional)", placeholder: "user:pass", text: $auth)

            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x3D6EA5))

            Text(status)
                .font(.system(size: 12))
                .foregroundColor(isError ? Color(hex: 0xFF6B6B) : Color(hex: 0x9AA4B1))
                .frame(minHeight: 14)
                .multilineTextAlignment(.center)

            if let savedWebURL {
                Divider()
                Link("Open Transmission Web Portal", destination: savedWebURL)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x7FB2E0))
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(hex: 0x182530))
        .foregroundColor(Color(hex: 0xE8EAED))
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0xC3C8CE))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(7)
                .background(Color(hex: 0x1F2F3D))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0x33475A)))
        }
    }

    private static func persistedWebURL() -> URL? {
        try? TransmissionConfig(host: Preferences.transmissionHost, auth: "").webURL
    }

    private func save() {
        let config: TransmissionConfig
        do {
            config = try TransmissionConfig(host: host, auth: auth)
        } catch {
            status = TransmissionError.text(for: error)
            isError = true
            return
        }

        status = "Checking connection…"
        isError = false

        Task {
            do {
                try await TransmissionClient.shared.testConnection(config: config)
            } catch {
                status = TransmissionError.text(for: error)
                isError = true
                return
            }

            // The credential is persisted before the host, so a keychain
            // failure leaves the saved configuration as it was rather than
            // stranding a new host next to a stale credential.
            do {
                try KeychainStore.save(auth)
            } catch {
                status = "Connected, but \(TransmissionError.text(for: error))"
                isError = true
                return
            }

            Preferences.transmissionHost = host
            savedWebURL = config.webURL
            status = "Saved."
            isError = false
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1.0
        )
    }
}
