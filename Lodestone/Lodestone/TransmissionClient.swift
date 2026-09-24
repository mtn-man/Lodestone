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

    private func rpcCall(
        method: String,
        arguments: [String: Any],
        config: TransmissionConfig,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let url = config.rpcURL
        let body = try JSONSerialization.data(withJSONObject: ["method": method, "arguments": arguments])

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

    func addMagnet(uri: String, config: TransmissionConfig, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        do {
            _ = try await rpcCall(method: "torrent-add", arguments: ["filename": uri], config: config, timeout: timeout)
        } catch {
            throw TransmissionError.message("transmission add failed (host=\(config.host)): \(TransmissionError.text(for: error))")
        }
    }

    func testConnection(config: TransmissionConfig, timeout: TimeInterval = TransmissionClient.defaultTimeout) async throws {
        do {
            _ = try await rpcCall(method: "session-get", arguments: [:], config: config, timeout: timeout)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw TransmissionError.message("could not reach transmission at \(config.host): timed out -- try a different address")
            }
            throw TransmissionError.message("could not reach transmission at \(config.host): \(TransmissionError.text(for: error))")
        }
    }
}
