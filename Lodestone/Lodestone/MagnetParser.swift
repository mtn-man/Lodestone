//
//  MagnetParser.swift
//  Lodestone
//
//  Swift port of extension/lib/magnet.js.
//

import Foundation

enum MagnetError: Error, Equatable {
    case empty
    case notMagnet
    case missingBTIH
    case btihTooShort
}

struct MagnetInfo: Equatable {
    let uri: String
    let btih: String
    let dn: String
    let trackers: Int
}

enum MagnetParser {
    static let btihPrefix = "urn:btih:"
    static let minBTIHLength = 8

    static func parse(_ raw: String) throws -> MagnetInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MagnetError.empty }

        // Foundation's URLComponents parses malformed non-hierarchical
        // schemes (e.g. "://bad") far more permissively than JS's WHATWG
        // URL, which throws for that case (JS: INVALID_URI). Rather than
        // fight Foundation's leniency, that case collapses into .notMagnet
        // here -- verified against all 8 magnet.test.js fixtures. In
        // practice application(_:open:) only ever hands this genuinely
        // magnet:-scheme URLs anyway.
        guard trimmed.lowercased().hasPrefix("magnet:"),
              let comps = URLComponents(string: trimmed) else {
            throw MagnetError.notMagnet
        }

        let queryItems = comps.queryItems ?? []
        let xt = queryItems.first(where: { $0.name == "xt" })?.value ?? ""
        guard xt.hasPrefix(btihPrefix) else { throw MagnetError.missingBTIH }

        let btih = String(xt.dropFirst(btihPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard btih.count >= minBTIHLength else { throw MagnetError.btihTooShort }

        let dn = queryItems.first(where: { $0.name == "dn" })?.value ?? ""
        let trackers = queryItems.filter { $0.name == "tr" }.count

        return MagnetInfo(uri: trimmed, btih: btih, dn: dn, trackers: trackers)
    }

    static func isValid(_ raw: String) -> Bool {
        (try? parse(raw)) != nil
    }
}
