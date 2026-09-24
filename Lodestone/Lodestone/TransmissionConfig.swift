//
//  TransmissionConfig.swift
//  Lodestone
//
//  A validated Transmission endpoint. The host and auth strings the user
//  typed are parsed and normalized exactly once -- here -- rather than
//  being re-trimmed and re-interpreted at each layer that touches them.
//  Holding one of these is proof the configuration parsed; the RPC layer
//  takes a config rather than raw strings so it has nothing left to
//  validate.
//

import Foundation

nonisolated struct TransmissionConfig: Equatable, Sendable {
    /// The host exactly as the user entered it, trimmed. Error messages
    /// echo this rather than the normalized URL, so "could not reach
    /// transmission at ..." shows the user their own input.
    let host: String
    let rpcURL: URL
    let webURL: URL
    /// nil when no credential is configured -- Transmission allows
    /// unauthenticated RPC, so absent auth is a valid state, not an error.
    let authHeader: String?

    private static let rpcPath = "/transmission/rpc"
    private static let webPath = "/transmission/web/"

    init(host rawHost: String, auth rawAuth: String) throws {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransmissionError.message("transmission host is empty")
        }

        // A bare "host:port" is not a URL until it has a scheme. Anything
        // URLComponents still can't parse after that -- a bare IPv6 literal
        // like "::1:9091", an embedded space -- is rejected rather than
        // silently resolved against a made-up host.
        let absolute = host.contains("://") ? host : "http://\(host)"
        guard let comps = URLComponents(string: absolute),
              let parsedHost = comps.host, !parsedHost.isEmpty else {
            throw TransmissionError.message(Self.malformed(host))
        }

        let scheme = (comps.scheme ?? "http").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw TransmissionError.message(
                "transmission host scheme must be http or https, not \(scheme)")
        }

        // URLComponents accepts any integer as a port; TCP does not.
        if let port = comps.port, !(1...65535).contains(port) {
            throw TransmissionError.message("\(port) is not a valid port -- use 1-65535")
        }

        // Credentials belong in the auth field, which puts them in the
        // Keychain. Silently dropping them here would leave the user with
        // a config that looks complete and 401s.
        guard comps.user == nil, comps.password == nil else {
            throw TransmissionError.message(
                "put credentials in the authentication field, not the host")
        }

        guard let rpcURL = Self.endpoint(scheme: scheme, host: parsedHost, port: comps.port, path: Self.rpcPath),
              let webURL = Self.endpoint(scheme: scheme, host: parsedHost, port: comps.port, path: Self.webPath) else {
            throw TransmissionError.message(Self.malformed(host))
        }

        let auth = rawAuth.trimmingCharacters(in: .whitespacesAndNewlines)
        if !auth.isEmpty && !auth.contains(":") {
            throw TransmissionError.message("transmission auth must be in \"user:pass\" form")
        }

        self.host = host
        self.rpcURL = rpcURL
        self.webURL = webURL
        self.authHeader = auth.isEmpty ? nil : "Basic \(Data(auth.utf8).base64EncodedString())"
    }

    /// Rebuilt from parsed components rather than concatenated, so any path,
    /// query, or fragment the user pasted along with the host is dropped
    /// instead of corrupting the endpoint.
    private static func endpoint(scheme: String, host: String, port: Int?, path: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = port
        comps.path = path
        return comps.url
    }

    private static func malformed(_ host: String) -> String {
        "\"\(host)\" is not a valid transmission host -- use host:port, e.g. 192.168.1.50:9091"
    }
}
