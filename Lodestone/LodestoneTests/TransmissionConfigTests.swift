//
//  TransmissionConfigTests.swift
//  LodestoneTests
//
//  The host field is free text typed by hand, so the interesting cases are
//  the near-misses: a bare IPv6 literal, a stray space, a pasted URL with a
//  path on it. Before TransmissionConfig these all resolved to *something*
//  and surfaced as "could not reach transmission at ...", which reads as a
//  dead server rather than a typo.
//
//  As with MagnetParserTests, this bundle has no TEST_HOST (see that file
//  for why), so TransmissionConfig.swift is a member of this target
//  directly. TransmissionClient.swift comes along with it for
//  TransmissionError; nothing here touches the network.
//

import Foundation
import Testing

nonisolated struct HostCase: CustomTestStringConvertible {
    let input: String
    let rpc: String
    var testDescription: String { input }
}

@Suite("TransmissionConfig")
nonisolated struct TransmissionConfigTests {

    static let accepted: [HostCase] = [
        HostCase(input: "192.168.1.50:9091", rpc: "http://192.168.1.50:9091/transmission/rpc"),
        HostCase(input: "nas.local", rpc: "http://nas.local/transmission/rpc"),
        HostCase(input: "http://nas.local:9091", rpc: "http://nas.local:9091/transmission/rpc"),
        HostCase(input: "https://nas.local:9091", rpc: "https://nas.local:9091/transmission/rpc"),
        HostCase(input: "HTTPS://nas.local", rpc: "https://nas.local/transmission/rpc"),
        HostCase(input: "[::1]:9091", rpc: "http://[::1]:9091/transmission/rpc"),
        HostCase(input: "  192.168.1.50:9091  ", rpc: "http://192.168.1.50:9091/transmission/rpc"),
        // A pasted endpoint keeps only its origin -- the path is ours to set.
        HostCase(input: "http://nas.local:9091/transmission/web/", rpc: "http://nas.local:9091/transmission/rpc"),
        HostCase(input: "nas.local:9091/", rpc: "http://nas.local:9091/transmission/rpc"),
        // Cleartext destinations that stay on a network the user controls.
        HostCase(input: "localhost:9091", rpc: "http://localhost:9091/transmission/rpc"),
        HostCase(input: "nas:9091", rpc: "http://nas:9091/transmission/rpc"),
        HostCase(input: "10.0.0.5:9091", rpc: "http://10.0.0.5:9091/transmission/rpc"),
        HostCase(input: "172.16.0.1:9091", rpc: "http://172.16.0.1:9091/transmission/rpc"),
        HostCase(input: "169.254.3.4:9091", rpc: "http://169.254.3.4:9091/transmission/rpc"),
        HostCase(input: "100.101.102.103:9091", rpc: "http://100.101.102.103:9091/transmission/rpc"),
        HostCase(input: "nas.tail1234.ts.net:9091", rpc: "http://nas.tail1234.ts.net:9091/transmission/rpc"),
        HostCase(input: "[fd7a:115c::1]:9091", rpc: "http://[fd7a:115c::1]:9091/transmission/rpc"),
        // A routable host is fine over TLS -- only the cleartext hop is refused.
        HostCase(input: "https://transmission.example.com", rpc: "https://transmission.example.com/transmission/rpc"),
    ]

    @Test("accepts well-formed hosts", arguments: accepted)
    func accepts(_ c: HostCase) throws {
        let config = try TransmissionConfig(host: c.input, auth: "")
        #expect(config.rpcURL.absoluteString == c.rpc)
    }

    static let rejected: [String] = [
        "",
        "   ",
        "::1:9091",           // bare IPv6 literal -- unparseable without brackets
        "my nas:9091",        // embedded space
        ":9091",              // port with no host
        "http://",
        "ftp://nas.local",    // scheme we cannot speak
        "nas.local:99999",    // port out of TCP range
        "nas.local:0",
        "user:pass@nas.local:9091",
        // Cleartext to a host the traffic would leave the network to reach.
        "transmission.example.com:9091",
        "http://transmission.example.com:9091",
        "8.8.8.8:9091",
        "172.32.0.1:9091",      // just outside RFC 1918 -- 172.16/12 ends at .31
        "100.128.0.1:9091",     // just outside CGNAT -- 100.64/10 ends at 100.127
        "[2606:4700::1111]:9091",
    ]

    @Test("rejects malformed hosts", arguments: rejected)
    func rejects(_ host: String) {
        #expect(throws: TransmissionError.self) {
            _ = try TransmissionConfig(host: host, auth: "")
        }
    }

    /// The whole point of the rejection: no malformed host may ever resolve
    /// to a reachable-looking URL. This is the regression guard for the old
    /// `http://invalid/...` fallback.
    @Test("no malformed host produces a URL", arguments: rejected)
    func rejectionNeverYieldsURL(_ host: String) {
        let config = try? TransmissionConfig(host: host, auth: "")
        #expect(config == nil)
    }

    /// Transmission sends its Basic auth header on every request, so the
    /// same host is a different proposition over http and https. The pair
    /// is asserted together so a failure here reads as the *scheme* rule
    /// breaking, not the host being rejected outright.
    @Test("a routable host is refused in the clear but allowed over TLS")
    func cleartextIsSchemeSpecific() throws {
        #expect(throws: TransmissionError.self) {
            _ = try TransmissionConfig(host: "http://transmission.example.com", auth: "")
        }
        let tls = try TransmissionConfig(host: "https://transmission.example.com", auth: "")
        #expect(tls.rpcURL.absoluteString == "https://transmission.example.com/transmission/rpc")
    }

    @Test("web URL points at the portal")
    func webURL() throws {
        let config = try TransmissionConfig(host: "nas.local:9091", auth: "")
        #expect(config.webURL.absoluteString == "http://nas.local:9091/transmission/web/")
    }

    @Test("host is preserved as typed, for error messages")
    func preservesTypedHost() throws {
        let config = try TransmissionConfig(host: "  NAS.local:9091  ", auth: "")
        #expect(config.host == "NAS.local:9091")
    }

    @Test("absent auth is valid and yields no header")
    func absentAuth() throws {
        #expect(try TransmissionConfig(host: "nas.local", auth: "").authHeader == nil)
        #expect(try TransmissionConfig(host: "nas.local", auth: "   ").authHeader == nil)
    }

    @Test("auth becomes a basic header")
    func basicAuth() throws {
        let config = try TransmissionConfig(host: "nas.local", auth: "  user:pass  ")
        #expect(config.authHeader == "Basic \(Data("user:pass".utf8).base64EncodedString())")
    }

    @Test("auth without a colon is rejected")
    func malformedAuth() {
        #expect(throws: TransmissionError.self) {
            _ = try TransmissionConfig(host: "nas.local", auth: "justausername")
        }
    }

    /// A password containing a colon is legal -- only the first colon splits.
    @Test("auth with extra colons is accepted")
    func colonInPassword() throws {
        let config = try TransmissionConfig(host: "nas.local", auth: "user:pa:ss")
        #expect(config.authHeader == "Basic \(Data("user:pa:ss".utf8).base64EncodedString())")
    }
}
