//
//  SettingsView.swift
//  Lodestone
//
//  A plain SwiftUI Form in the system appearance. This deliberately no
//  longer reproduces the old extension/popup.html dark theme: that palette
//  was a web popup's, hardcoded in hex, and it forced a dark window on a
//  machine in Light Mode and overrode the user's accent colour. Every
//  colour here is semantic, so the window follows the system.
//
//  The save flow is unchanged and is the reason this isn't a live-applying
//  settings pane: validate locally -> test connectivity against the daemon
//  -> persist only on success.
//

import SwiftUI

struct SettingsView: View {
    @State private var host: String = Preferences.transmissionHost
    @State private var username: String
    @State private var password: String
    @State private var status: String
    @State private var isError: Bool
    @State private var isChecking: Bool = false
    /// The web-portal URL for the currently persisted host, or nil if none
    /// is configured. Derived from the saved host rather than tracked as a
    /// second copy of it, so the link is shown exactly when it resolves.
    @State private var savedWebURL: URL? = SettingsView.persistedWebURL()
    /// Set only when notification feedback won't be visible. Notifications
    /// are the app's only output, so that state otherwise leaves a working
    /// app that appears to do nothing, with no hint as to why.
    @State private var notificationWarning: String?

    init() {
        // A failed keychain read must not present as "no credential set":
        // the fields would come up blank and the obvious reading is that
        // one was never configured, which sends the user to the wrong
        // problem.
        do {
            let stored = try KeychainStore.load() ?? ""
            let parts = Self.split(stored)
            _username = State(initialValue: parts.user)
            _password = State(initialValue: parts.password)
            _status = State(initialValue: "")
            _isError = State(initialValue: false)
        } catch {
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _status = State(initialValue: TransmissionError.text(for: error))
            _isError = State(initialValue: true)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $host, prompt: Text("192.168.1.50:9091"))
                TextField("Username", text: $username, prompt: Text("Optional"))
                SecureField("Password", text: $password, prompt: Text("Optional"))
            } header: {
                Text("Transmission Server")
            } footer: {
                Text("Magnet links you click are sent here instead of opening in a local torrent app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isChecking || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savedWebURL {
                    Link(destination: savedWebURL) {
                        Label("Open Transmission Web Portal", systemImage: "arrow.up.forward.app")
                    }
                }
            }

            if let notificationWarning {
                Section {
                    Label(notificationWarning, systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Notification Settings…") {
                        NotificationFeedback.openNotificationSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .task {
            notificationWarning = await NotificationFeedback.unavailableReason()
        }
    }

    /// The credential is stored as the single "user:pass" string that basic
    /// auth wants, but presented as two fields because that is what a macOS
    /// credential form looks like -- and because a password belongs in a
    /// SecureField, not in plain text on screen. Splitting on the first
    /// colon only keeps a colon-bearing password intact.
    private static func split(_ auth: String) -> (user: String, password: String) {
        guard let separator = auth.firstIndex(of: ":") else { return (auth, "") }
        return (String(auth[..<separator]), String(auth[auth.index(after: separator)...]))
    }

    private var combinedAuth: String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.isEmpty && password.isEmpty { return "" }
        return "\(user):\(password)"
    }

    private static func persistedWebURL() -> URL? {
        try? TransmissionConfig(host: Preferences.transmissionHost, auth: "").webURL
    }

    private func save() {
        let auth = combinedAuth
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
        isChecking = true

        Task {
            defer { isChecking = false }

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
