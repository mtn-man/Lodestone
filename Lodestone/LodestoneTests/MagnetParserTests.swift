//
//  MagnetParserTests.swift
//  LodestoneTests
//
//  MagnetParser's contract is "accept exactly what Transmission accepts,"
//  so these cases are written against libtransmission/magnet-metainfo.cc
//  (`tr_magnet_metainfo::parseMagnet`) rather than against any behavior of
//  Lodestone's own. The reject cases carry as much weight as the accept
//  cases: several of them are links a reasonable person would assume are
//  valid, which Transmission nonetheless refuses.
//
//  This bundle has no TEST_HOST. Running the app to host the tests would
//  fire applicationDidFinishLaunching, whose claimMagnetHandler() mutates
//  the *system-wide* Launch Services default handler -- a real side effect
//  on the developer's machine as a side effect of running tests.
//  MagnetParser.swift is a member of this target directly instead, which
//  it can be because it depends on nothing beyond Foundation.
//

import Foundation
import Testing

private nonisolated enum Hash {
    /// 40 hex characters -- `tr_sha1_from_string`.
    static let hex40 = "abcdef0123456789abcdef0123456789abcdef01"
    /// 32 base32 characters -- `parseBase32Hash`.
    static let base32 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    /// 64 hex characters, the v2 digest that follows the `1220` multihash tag.
    static let hex64 = String(repeating: "a", count: 64)
}

/// Named so failures identify themselves by case rather than by index.
nonisolated struct MagnetCase: Sendable, CustomTestStringConvertible {
    let name: String
    let uri: String
    var testDescription: String { name }
}

@Suite("MagnetParser matches libtransmission's parseMagnet")
nonisolated struct MagnetParserTests {

    // MARK: - Accepted

    static let accepted: [MagnetCase] = [
        .init(name: "40-char hex info hash",
              uri: "magnet:?xt=urn:btih:\(Hash.hex40)"),
        .init(name: "32-char base32 info hash",
              uri: "magnet:?xt=urn:btih:\(Hash.base32)"),
        // tr_sha1_from_string validates with isxdigit, which is case-blind.
        .init(name: "uppercase hex info hash",
              uri: "magnet:?xt=urn:btih:\(Hash.hex40.uppercased())"),
        // The regression this suite exists for: the parser used to read
        // only the first `xt` and reject anything whose leading topic was
        // some other URN.
        .init(name: "btih is the second xt topic",
              uri: "magnet:?xt=urn:ed2k:0123456789ABCDEF&xt=urn:btih:\(Hash.hex40)"),
        .init(name: "btih follows other query keys",
              uri: "magnet:?dn=Example&tr=udp://tracker.example:80&xt=urn:btih:\(Hash.hex40)"),
        // Hybrid v1+v2 resolves on its v1 topic.
        .init(name: "hybrid v1 + v2",
              uri: "magnet:?xt=urn:btih:\(Hash.hex40)&xt=urn:btmh:1220\(Hash.hex64)"),
        // parseMagnet assigns unconditionally as it scans, so a later
        // valid hash overwrites an earlier unusable one.
        .init(name: "malformed btih followed by a valid one",
              uri: "magnet:?xt=urn:btih:short&xt=urn:btih:\(Hash.hex40)"),
    ]

    @Test("accepts", arguments: accepted)
    func accepts(_ testCase: MagnetCase) throws {
        let info = try MagnetParser.parse(testCase.uri)
        #expect(!info.btih.isEmpty)
        // The URI is forwarded to Transmission verbatim, so it must survive
        // parsing unmodified apart from the outer whitespace strip.
        #expect(info.uri == testCase.uri)
    }

    @Test("picks the btih topic out of a multi-topic link")
    func selectsBTIHAmongTopics() throws {
        let info = try MagnetParser.parse(
            "magnet:?xt=urn:ed2k:0123456789ABCDEF&xt=urn:btih:\(Hash.hex40)")
        #expect(info.btih == Hash.hex40)
    }

    @Test("last valid btih wins, matching parseMagnet's unconditional assignment")
    func lastValidHashWins() throws {
        let second = String(repeating: "b", count: 40)
        let info = try MagnetParser.parse(
            "magnet:?xt=urn:btih:\(Hash.hex40)&xt=urn:btih:\(second)")
        #expect(info.btih == second)
    }

    // MARK: - Rejected

    /// Links Transmission itself refuses. Accepting any of these would not
    /// make it work -- it would only move the failure to the daemon and
    /// make the resulting message vaguer.
    static let rejected: [MagnetCase] = [
        // Only `tr` gets the indexed-prefix treatment (trac ticket 3341);
        // the xt key is compared with ==.
        .init(name: "xt.1 indexed topic form",
              uri: "magnet:?xt.1=urn:btih:\(Hash.hex40)"),
        // tr_strv_starts_with is case-sensitive.
        .init(name: "uppercase URN:BTIH: prefix",
              uri: "magnet:?xt=URN:BTIH:\(Hash.hex40)"),
        // The v2 branch fills in info_hash2_ but never sets got_hash, so
        // parseMagnet returns false for a link carrying no v1 topic.
        .init(name: "v2-only btmh link",
              uri: "magnet:?xt=urn:btmh:1220\(Hash.hex64)"),
        // Length is exact, not a minimum.
        .init(name: "hash shorter than 40 hex",
              uri: "magnet:?xt=urn:btih:abcdef0123"),
        .init(name: "hash one char short of 40",
              uri: "magnet:?xt=urn:btih:\(Hash.hex40.dropLast())"),
        .init(name: "40 characters but not hex",
              uri: "magnet:?xt=urn:btih:\(String(repeating: "z", count: 40))"),
        .init(name: "31 base32 characters",
              uri: "magnet:?xt=urn:btih:\(Hash.base32.dropLast())"),
        // Transmission percent-decodes dn and tr, but compares xt raw.
        .init(name: "percent-encoded xt value",
              uri: "magnet:?xt=urn%3Abtih%3A\(Hash.hex40)"),
        .init(name: "no xt topic at all",
              uri: "magnet:?dn=Example&tr=udp://tracker.example:80"),
        .init(name: "not a magnet scheme",
              uri: "https://example.com/?xt=urn:btih:\(Hash.hex40)"),
        .init(name: "empty string",
              uri: ""),
    ]

    @Test("rejects", arguments: rejected)
    func rejects(_ testCase: MagnetCase) {
        #expect(throws: MagnetError.self) {
            try MagnetParser.parse(testCase.uri)
        }
    }

    @Test("reports the specific reason for rejection", arguments: [
        ("", MagnetError.empty),
        ("   \n ", MagnetError.empty),
        ("https://example.com", MagnetError.notMagnet),
        ("magnet:?dn=Example", MagnetError.missingBTIH),
        ("magnet:?xt=urn:btmh:1220\(Hash.hex64)", MagnetError.missingBTIH),
        ("magnet:?xt=urn:btih:abcdef0123", MagnetError.malformedBTIH),
    ])
    func rejectionReason(uri: String, expected: MagnetError) {
        #expect(throws: expected) {
            try MagnetParser.parse(uri)
        }
    }

    // MARK: - Surrounding metadata

    @Test("strips surrounding whitespace before parsing, as tr_strv_strip does")
    func stripsOuterWhitespace() throws {
        let info = try MagnetParser.parse("  \n magnet:?xt=urn:btih:\(Hash.hex40)  \t")
        #expect(info.btih == Hash.hex40)
        #expect(info.uri == "magnet:?xt=urn:btih:\(Hash.hex40)")
    }

    @Test("percent-decodes dn, which Transmission decodes before use")
    func decodesDisplayName() throws {
        let info = try MagnetParser.parse(
            "magnet:?xt=urn:btih:\(Hash.hex40)&dn=Some%20Name")
        #expect(info.dn == "Some Name")
    }

    @Test("counts plain tr and indexed tr.N trackers alike")
    func countsTrackers() throws {
        let info = try MagnetParser.parse("""
            magnet:?xt=urn:btih:\(Hash.hex40)\
            &tr=udp://a.example:80&tr.1=udp://b.example:80&tr.2=udp://c.example:80
            """)
        #expect(info.trackers == 3)
    }

    @Test("reports no trackers when the link carries none")
    func countsZeroTrackers() throws {
        let info = try MagnetParser.parse("magnet:?xt=urn:btih:\(Hash.hex40)")
        #expect(info.trackers == 0)
        #expect(info.dn.isEmpty)
    }
}
