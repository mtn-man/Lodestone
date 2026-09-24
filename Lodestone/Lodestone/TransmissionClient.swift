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

    static func text(for error: Error) -> String {
        if let e = error as? TransmissionError, case .message(let m) = e { return m }
        return error.localizedDescription
    }
}

actor TransmissionClient {
    static let shared = TransmissionClient()
    static let defaultTimeout: TimeInterval = 10

    private var cachedSessionID: String = ""

    private static func hostURL(_ hostInput: String, path: String) -> URL {
        let host = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = host.contains("://") ? host : "http://\(host)"
        if let comps = URLComponents(string: raw), let h = comps.host, !h.isEmpty {
            let scheme = comps.scheme ?? "http"
            let port = comps.port.map { ":\($0)" } ?? ""
            if let url = URL(string: "\(scheme)://\(h)\(port)\(path)") {
                return url
            }
        }
        // Never throws -- falls back to naive concatenation, matching the
        // JS version's try/catch fallback behavior exactly.
        return URL(string: "http://\(host)\(path)") ?? URL(string: "http://invalid\(path)")!
    }

    nonisolated static func rpcURL(_ host: String) -> URL { hostURL(host, path: "/transmission/rpc") }
    nonisolated static func webURL(_ host: String) -> URL { hostURL(host, path: "/transmission/web/") }

    nonisolated static func validateConfig(host: String, auth: String) throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransmissionError.message("transmission host is empty")
        }
        let trimmedAuth = auth.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuth.isEmpty && !trimmedAuth.contains(":") {
            throw TransmissionError.message("transmission auth must be in \"user:pass\" form")
        }
    }

    private func rpcCall(
        method: String,
        arguments: [String: Any],
        host: String,
        auth: String,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let url = Self.rpcURL(host)
        let body = try JSONSerialization.data(withJSONObject: ["method": method, "arguments": arguments])
        let trimmedAuth = auth.trimmingCharacters(in: .whitespacesAndNewlines)
        let authHeader: String? = trimmedAuth.isEmpty
            ? nil
            : "Basic \(Data(trimmedAuth.utf8).base64EncodedString())"

        func doFetch(sessionID: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !sessionID.isEmpty {
                request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            }
            if let authHeader {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransmissionError.message("transmission rpc: no HTTP response")
            }
            return (data, http)
        }

        var (data, response) = try await doFetch(sessionID: cachedSessionID)
        if response.statusCode == 409 {
            cachedSessionID = response.value(forHTTPHeaderField: "X-Transmission-Session-Id") ?? ""
            (data, response) = try await doFetch(sessionID: cachedSessionID)
        }

        guard response.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TransmissionError.message("transmission rpc: unexpected status \(response.statusCode): \(text)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransmissionError.message("transmission rpc \(method): invalid response")
        }
        guard let result = json["result"] as? String, result == "success" else {
            let result = (json["result"] as? String) ?? "unknown error"
            throw TransmissionError.message("transmission rpc \(method): \(result)")
        }
        return (json["arguments"] as? [String: Any]) ?? [:]
    }

    func addMagnet(uri: String, host: String, auth: String, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        try Self.validateConfig(host: host, auth: auth)
        do {
            _ = try await rpcCall(method: "torrent-add", arguments: ["filename": uri], host: host, auth: auth, timeout: timeout)
        } catch {
            throw TransmissionError.message("transmission add failed (host=\(host)): \(TransmissionError.text(for: error))")
        }
    }

    func testConnection(host: String, auth: String, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        try Self.validateConfig(host: host, auth: auth)
        do {
            _ = try await rpcCall(method: "session-get", arguments: [:], host: host, auth: auth, timeout: timeout)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw TransmissionError.message("could not reach transmission at \(host): timed out -- try a different address")
            }
            throw TransmissionError.message("could not reach transmission at \(host): \(TransmissionError.text(for: error))")
        }
    }
}
