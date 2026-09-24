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
