//
//  TransmissionClient.swift
//  Lodestone
//
//  Swift port of extension/lib/transmission-client.js.
//

import Foundation

enum TransmissionError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

actor TransmissionClient {
    static let shared = TransmissionClient()
    static let defaultTimeout: TimeInterval = 10

    // Keyed by host rather than a single value: Lodestone reconstructs
    // TransmissionConfig fresh on every call (from Preferences + Keychain),
    // so a bare cached ID would carry the previous host's session ID into
    // the first request against a newly-configured one -- harmless (a
    // stale ID just gets rejected with a 409 and retried) but avoidable.
    // Unbounded growth isn't a concern: this is a personal, single-user
    // app with at most a handful of hosts ever configured in its lifetime.
    private var cachedSessionIDs: [String: String] = [:]

    // Transmission's RPC envelope, modelled as Codable types rather than
    // [String: Any]. The dictionaries were the reason: they are not
    // Sendable, so passing them in and out of this actor is silent under
    // Swift 5 but a hard error in Swift 6 language mode. Concrete types
    // also retire the JSONSerialization casts below them.

    private struct Request<Arguments: Encodable & Sendable>: Encodable {
        let method: String
        let arguments: Arguments
    }

    /// Only `result` is read. Transmission also returns an `arguments`
    /// object, but nothing here consumes it, and decoding a payload we
    /// ignore would be one more shape to keep in step with the daemon.
    private struct Response: Decodable {
        let result: String
    }

    private struct NoArguments: Encodable, Sendable {}

    private struct TorrentAdd: Encodable, Sendable {
        let filename: String
    }

    private func rpcCall<Arguments: Encodable & Sendable>(
        method: String,
        arguments: Arguments,
        config: TransmissionConfig,
        timeout: TimeInterval
    ) async throws {
        let url = config.rpcURL
        let body = try JSONEncoder().encode(Request(method: method, arguments: arguments))

        func doFetch(sessionID: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !sessionID.isEmpty {
                request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            }
            if let authHeader = config.authHeader {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransmissionError.message("transmission rpc: no HTTP response")
            }
            return (data, http)
        }

        var (data, response) = try await doFetch(sessionID: cachedSessionIDs[config.host] ?? "")
        if response.statusCode == 409 {
            let sessionID = response.value(forHTTPHeaderField: "X-Transmission-Session-Id") ?? ""
            cachedSessionIDs[config.host] = sessionID
            (data, response) = try await doFetch(sessionID: sessionID)
        }

        guard response.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TransmissionError.message("transmission rpc: unexpected status \(response.statusCode): \(text)")
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TransmissionError.message("transmission rpc \(method): invalid response")
        }
        guard decoded.result == "success" else {
            throw TransmissionError.message("transmission rpc \(method): \(decoded.result)")
        }
    }

    func addMagnet(uri: String, config: TransmissionConfig, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        do {
            try await rpcCall(method: "torrent-add", arguments: TorrentAdd(filename: uri), config: config, timeout: timeout)
        } catch {
            throw TransmissionError.message("transmission add failed (host=\(config.host)): \(error.localizedDescription)")
        }
    }

    func testConnection(config: TransmissionConfig, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        do {
            try await rpcCall(method: "session-get", arguments: NoArguments(), config: config, timeout: timeout)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw TransmissionError.message("could not reach transmission at \(config.host): timed out -- try a different address")
            }
            throw TransmissionError.message("could not reach transmission at \(config.host): \(error.localizedDescription)")
        }
    }
}
