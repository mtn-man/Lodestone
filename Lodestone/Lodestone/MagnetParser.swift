//
//  MagnetParser.swift
//  Lodestone
//
//  Gate for incoming magnet: URLs. Lodestone forwards the URI to
//  Transmission verbatim, so this parser's only job is to decide what
//  Transmission itself would accept -- rejecting locally (fast, clear
//  message) rather than round-tripping to the daemon for a refusal.
//
//  Mirrors libtransmission/magnet-metainfo.cc `tr_magnet_metainfo::
//  parseMagnet`; each divergence from the obvious Swift spelling is
//  annotated with the libtransmission behavior it matches.
//

import Foundation

enum MagnetError: Error, Equatable {
    case empty
    case notMagnet
    case missingBTIH
    case malformedBTIH
}

struct MagnetInfo: Equatable {
    let uri: String
    let btih: String
    let dn: String
    let trackers: Int
}

nonisolated enum MagnetParser {
    static let btihPrefix = "urn:btih:"

    // Exact lengths, not minimums: parseHash accepts a 40-char hex SHA-1
    // (tr_sha1_from_string) or a 32-char base32 SHA-1 (parseBase32Hash),
    // and nothing else.
    private static let hexHashLength = 40
    private static let base32HashLength = 32

    static func parse(_ raw: String) throws -> MagnetInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MagnetError.empty }

        // Foundation's URLComponents parses malformed non-hierarchical
        // schemes (e.g. "://bad") far more permissively than a strict URL
        // parser would, so that case collapses into .notMagnet here. In
        // practice application(_:open:) only ever hands this genuinely
        // magnet:-scheme URLs anyway.
        guard trimmed.lowercased().hasPrefix("magnet:"),
              let comps = URLComponents(string: trimmed) else {
            throw MagnetError.notMagnet
        }

        // Transmission percent-decodes `dn` and `tr` but compares `xt`
        // raw, so the topic scan has to run over the still-encoded items:
        // Foundation would otherwise decode `xt=urn%3Abtih%3A...` into a
        // match that Transmission rejects.
        let encodedItems = comps.percentEncodedQueryItems ?? []

        // parseMagnet loops over *every* query entry rather than stopping
        // at the first `xt`, so a link whose first topic is some other URN
        // (urn:ed2k:, urn:sha1:, ...) still resolves. Assignment is
        // unconditional inside the loop, so the last valid hash wins.
        //
        // The key is matched exactly: `xt.1`/`xt.2` are *not* recognized
        // (only `tr.` gets the indexed-prefix treatment), and the prefix
        // compare is case-sensitive, so `URN:BTIH:` is not recognized
        // either. Both are rejected upstream; matching that here keeps the
        // failure local instead of turning it into a daemon-side error.
        var btih: String?
        var sawBTIHTopic = false
        for item in encodedItems where item.name == "xt" {
            guard let value = item.value, value.hasPrefix(btihPrefix) else { continue }
            sawBTIHTopic = true
            let hash = String(value.dropFirst(btihPrefix.count))
            if isValidHash(hash) {
                btih = hash
            }
        }

        guard let btih else {
            // parseMagnet returns a bare false for both cases; splitting
            // them only sharpens the message shown to the user.
            //
            // A v2-only link lands in .missingBTIH deliberately: the
            // `urn:btmh:1220` branch fills in info_hash2_ but never sets
            // got_hash, so Transmission refuses a magnet carrying no v1
            // topic. Hybrid v1+v2 links match on their btih topic here.
            throw sawBTIHTopic ? MagnetError.malformedBTIH : MagnetError.missingBTIH
        }

        // dn and tr *are* decoded before use upstream, so these read from
        // the decoded items. `tr.` is the indexed tracker form Transmission
        // accepts alongside plain `tr`.
        let decodedItems = comps.queryItems ?? []
        let dn = decodedItems.first(where: { $0.name == "dn" })?.value ?? ""
        let trackers = decodedItems.filter { $0.name == "tr" || $0.name.hasPrefix("tr.") }.count

        return MagnetInfo(uri: trimmed, btih: btih, dn: dn, trackers: trackers)
    }

    static func isValid(_ raw: String) -> Bool {
        (try? parse(raw)) != nil
    }

    private static func isValidHash(_ hash: String) -> Bool {
        if hash.count == hexHashLength, hash.allSatisfy(isASCIIHexDigit) { return true }
        if hash.count == base32HashLength, hash.allSatisfy(isBase32Digit) { return true }
        return false
    }

    // C's isxdigit is ASCII-only; Character.isHexDigit alone would also
    // accept full-width and other Unicode hex digits.
    private static func isASCIIHexDigit(_ c: Character) -> Bool {
        c.isASCII && c.isHexDigit
    }

    // Base32Lookup maps A-Z and a-z to 0-25 and 2-7 to 26-31; every other
    // byte is 0xFF, and parseBase32Hash rejects the string if any
    // character misses.
    private static func isBase32Digit(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return ("A"..."Z").contains(c) || ("a"..."z").contains(c) || ("2"..."7").contains(c)
    }
}
