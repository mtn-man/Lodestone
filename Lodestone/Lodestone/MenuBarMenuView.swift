//
//  MenuBarMenuView.swift
//  Lodestone
//
//  Deliberately minimal -- no torrent list, no history (see CLAUDE.md's
//  scope-creep guardrail: this app's entire job is "click magnet link ->
//  add to remote host," nothing more).
//

import SwiftUI

private enum ConnectionStatus {
    case checking
    case connected
    case failed(String)
    case unconfigured
}

struct MenuBarMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @State private var status: ConnectionStatus = .checking

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // openSettings rather than SettingsLink, which takes no action
            // closure. The activate() here is for the case SettingsView's
            // onAppear cannot cover: re-selecting this item while the window
            // is already open, where the view never appears again.
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            // HIG names this "Quit <App Name>", not bare "Quit". The
            // shortcut only fires while this menu is open -- an accessory
            // app has no menu bar of its own for a global Command-Q to
            // live in.
            Button("Quit Lodestone") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .task {
            // .window style (see LodestoneApp) tears this view down and
            // rebuilds it on every open, so .task reliably reruns each
            // time -- unlike .menu style, whose content view is built once
            // and never revisited.
            await checkConnection()
        }
    }

    private var statusText: String {
        switch status {
        case .checking: return "Checking connection…"
        case .connected: return "Connected ✓"
        case .failed(let message): return "Error: \(message)"
        case .unconfigured: return "No Transmission server configured"
        }
    }

    private var statusIsError: Bool {
        if case .failed = status { return true }
        if case .unconfigured = status { return true }
        return false
    }

    private func checkConnection() async {
        status = .checking

        let host = Preferences.transmissionHost
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .unconfigured
            return
        }

        let auth = (try? KeychainStore.load()) ?? ""
        guard let config = try? TransmissionConfig(host: host, auth: auth) else {
            status = .unconfigured
            return
        }

        do {
            try await TransmissionClient.shared.testConnection(config: config)
            status = .connected
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
