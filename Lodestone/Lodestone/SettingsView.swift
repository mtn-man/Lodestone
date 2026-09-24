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
            _status = State(initialValue: error.localizedDescription)
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
        // Captured once (the scene reuses one NSWindow), then raised on
        // every open -- onAppear fires each time, makeNSView does not.
        .background(WindowAccessor { window in
            SettingsWindowRaiser.window = window
            SettingsWindowRaiser.raise()
        })
        .onAppear {
            // The window is not attached yet at onAppear time.
            DispatchQueue.main.async { SettingsWindowRaiser.raise() }
        }
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
            status = error.localizedDescription
            isError = true
            return
        }

        status = "Checking connection…"
        isError = false
        isChecking = true

        // This Task mutates @State directly, which is only safe because the
        // project sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor: the closure
        // inherits main-actor isolation. Dropping that build setting would
        // make every assignment here a main-thread violation, so it is not a
        // tidy-up candidate.
        Task {
            defer { isChecking = false }

            do {
                try await TransmissionClient.shared.testConnection(config: config)
            } catch {
                status = error.localizedDescription
                isError = true
                return
            }

            // The credential is persisted before the host, so a keychain
            // failure leaves the saved configuration as it was rather than
            // stranding a new host next to a stale credential.
            do {
                try KeychainStore.save(auth)
            } catch {
                status = "Connected, but \(error.localizedDescription)"
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

/// Brings the Settings window forward.
///
/// An accessory app is never activated on its own behalf, and from the
/// Settings scene's built-in Command-comma it is not granted activation at
/// all: NSApp.activate() returns having done nothing and the window is
/// restored to its saved frame behind whatever is in front. With no Dock
/// icon there is then no way to reach it. orderFrontRegardless raises it
/// without needing a grant; activate() is still requested so the window
/// takes focus in the cases where that is allowed.
private enum SettingsWindowRaiser {
    static weak var window: NSWindow?

    static func raise() {
        NSApp.activate()
        window?.orderFrontRegardless()
    }
}

/// Runs a closure with the NSWindow hosting this view, once it exists.
/// SwiftUI offers no first-class way to reach it. Note makeNSView runs only
/// when the representable is first created, not on every reopen.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
