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
    @State private var saveStatus = TransientStatus()
    @State private var isChecking: Bool = false
    /// The web-portal URL for the currently persisted host, or nil if none
    /// is configured. Derived from the saved host rather than tracked as a
    /// second copy of it, so the link is shown exactly when it resolves.
    @State private var savedWebURL: URL? = Preferences.transmissionWebURL
    /// Result of "Check Connection", kept separate from `saveStatus`/
    /// `isChecking` above -- those describe the Save flow (which tests the
    /// form fields before persisting them), this describes a check against
    /// the config that's actually persisted and in use for magnet adds.
    /// Deliberately not run automatically on window appear: opening
    /// Settings is far more frequent than wanting to know the daemon's
    /// reachability, so an explicit button avoids a network round-trip on
    /// every open.
    @State private var isCheckingConnection = false
    @State private var connectionStatus = TransientStatus()
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
        } catch {
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _saveStatus = State(initialValue: TransientStatus(text: error.localizedDescription, isError: true))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $host, prompt: Text("192.168.1.50:9091"))
                TextField("Username", text: $username, prompt: Text("optional"))
                SecureField("Password", text: $password, prompt: Text("optional"))

                HStack(spacing: 8) {
                    Spacer()
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isChecking || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }

                if let text = saveStatus.text {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(saveStatus.isError ? Color.red : (isChecking ? Color.secondary : Color.green))
                        .fixedSize(horizontal: false, vertical: true)
                }

            } header: {
                Text("Transmission Server")
            } footer: {
                Text("Magnet links you click are sent here instead of opening in a local torrent app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    Button("Check Connection", action: checkConnection)
                        .disabled(isCheckingConnection)
                    Spacer()
                    if isCheckingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else if let text = connectionStatus.text {
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(connectionStatus.isError ? Color.red : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let savedWebURL {
                Section {
                    HStack {
                        Spacer()
                        Link(destination: savedWebURL) {
                            Label("Open Transmission Web Portal", systemImage: "arrow.up.forward.app")
                        }
                        Spacer()
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
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

    private func save() {
        let auth = combinedAuth
        let config: TransmissionConfig
        do {
            config = try TransmissionConfig(host: host, auth: auth)
        } catch {
            saveStatus.show(error.localizedDescription, isError: true)
            return
        }

        saveStatus.showInProgress("Checking connection…")
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
                saveStatus.show(error.localizedDescription, isError: true)
                return
            }

            // The credential is persisted before the host, so a keychain
            // failure leaves the saved configuration as it was rather than
            // stranding a new host next to a stale credential.
            do {
                try KeychainStore.save(auth)
            } catch {
                saveStatus.show("Connected, but \(error.localizedDescription)", isError: true)
                return
            }

            Preferences.transmissionHost = config.host
            savedWebURL = config.webURL
            saveStatus.show("Saved.", isError: false)
        }
    }

    /// Tests the persisted config -- Preferences.transmissionHost plus the
    /// saved Keychain credential -- not the (possibly unsaved) form fields
    /// above, which is what "Save" tests instead.
    private func checkConnection() {
        isCheckingConnection = true

        Task {
            defer { isCheckingConnection = false }

            let host = Preferences.transmissionHost
            guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                connectionStatus.show("No server configured", isError: true)
                return
            }

            let auth = (try? KeychainStore.load()) ?? ""
            let config: TransmissionConfig
            do {
                config = try TransmissionConfig(host: host, auth: auth)
            } catch {
                connectionStatus.show(error.localizedDescription, isError: true)
                return
            }

            do {
                try await TransmissionClient.shared.testConnection(config: config)
                connectionStatus.show("Connected", isError: false)
            } catch {
                connectionStatus.show(error.localizedDescription, isError: true)
            }
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

/// A status message that clears itself a few seconds after being shown,
/// guarded by a token so a slower, earlier `show` can't clear a status a
/// later one just set. Backs both the Save flow's result and the "Check
/// Connection" result in `SettingsView` -- previously two hand-rolled copies
/// of this same pattern.
@Observable
private final class TransientStatus {
    private(set) var text: String?
    private(set) var isError: Bool
    private var token = UUID()

    init(text: String? = nil, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    /// Shows a terminal result (a success message or an error) and clears
    /// it after a few seconds.
    func show(_ text: String, isError: Bool) {
        let token = UUID()
        self.token = token
        self.text = text
        self.isError = isError

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if self?.token == token { self?.text = nil }
        }
    }

    /// Shows a non-terminal message (e.g. "Checking connection…") that
    /// stays until superseded by a `show`. Still bumps the token, so a
    /// clear timer from an earlier `show` can't wipe this out.
    func showInProgress(_ text: String) {
        token = UUID()
        self.text = text
        isError = false
    }
}
