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

        // Transmission's Basic auth header rides on every RPC request, so
        // cleartext http is confined to destinations the traffic cannot
        // leave a network the user controls to reach. This is the narrow
        // transport-security rule Info.plist cannot express: ATS exceptions
        // are written against domains known at build time, and this host is
        // typed by the user at runtime, so the app has to enforce it (see
        // README "Gotchas").
        if scheme == "http", !Self.allowsCleartext(parsedHost) {
            throw TransmissionError.message(
                "\(parsedHost) is not a local address -- use https:// so the "
                    + "transmission password is not sent in the clear")
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

    /// Whether plain http to this host stays inside the user's own network.
    /// Deliberately broader than ATS's `NSAllowsLocalNetworking`, which
    /// covers only RFC 1918 and would reject the CGNAT range a Tailscale
    /// host lives in -- the reason that exception was rejected in favour of
    /// `NSAllowsArbitraryLoads` plus this check.
    private static func allowsCleartext(_ rawHost: String) -> Bool {
        // URLComponents strips the brackets from an IPv6 literal, but trim
        // them anyway so this holds either way.
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host.contains(":") { return isLocalIPv6(host) }
        if let octets = ipv4Octets(host) { return isLocalIPv4(octets) }
        return isLocalName(host)
    }

    /// nil for anything that is not a dotted-quad literal -- a hostname that
    /// merely starts with digits is a name, and is judged as one.
    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    private static func isLocalIPv4(_ octets: [Int]) -> Bool {
        switch (octets[0], octets[1]) {
        case (127, _): return true          // loopback
        case (10, _): return true           // RFC 1918
        case (172, 16...31): return true    // RFC 1918
        case (192, 168): return true        // RFC 1918
        case (100, 64...127): return true   // RFC 6598 CGNAT -- where Tailscale lives
        case (169, 254): return true        // link-local
        default: return false
        }
    }

    /// Matched on the textual first group, which is unambiguous here: the
    /// leading group of an address in these ranges cannot be written with a
    /// leading zero or elided, so the prefix is always spelled out.
    private static func isLocalIPv6(_ host: String) -> Bool {
        if host == "::1" { return true }                                   // loopback
        if host.hasPrefix("fc") || host.hasPrefix("fd") { return true }    // fc00::/7 unique-local
        // fe80::/10 -- first group fe80 through febf.
        if let first = host.split(separator: ":").first, first.count == 4,
           first.hasPrefix("fe"), let nibble = Int(first.dropFirst(2).prefix(1), radix: 16),
           (8...11).contains(nibble) {
            return true
        }
        return false
    }

    private static func isLocalName(_ host: String) -> Bool {
        if host == "localhost" { return true }
        if host.hasSuffix(".local") { return true }    // mDNS/Bonjour
        if host.hasSuffix(".ts.net") { return true }   // Tailscale MagicDNS -- resolves into 100.64.0.0/10
        // An unqualified single-label name resolves through the local
        // search domain, so it cannot name a host off the network either.
        return !host.contains(".")
    }

    private static func malformed(_ host: String) -> String {
        "\"\(host)\" is not a valid transmission host -- use host:port, e.g. 192.168.1.50:9091"
    }
}
