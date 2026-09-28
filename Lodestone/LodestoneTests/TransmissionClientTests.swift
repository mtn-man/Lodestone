//
//  TransmissionClientTests.swift
//  LodestoneTests
//
//  TransmissionClient talks to the network through TransmissionTransport,
//  so these tests substitute MockTransport -- a scripted, in-memory stand-in
//  -- rather than a mocking framework or a local HTTP server. As with
//  MagnetParserTests/TransmissionConfigTests, this bundle has no TEST_HOST
//  (see MagnetParserTests for why), so TransmissionClient.swift and
//  TransmissionConfig.swift are members of this target directly.
//

import Foundation
import Testing

/// Scripted responses returned in order, one per `send`. Throwing
/// `MockTransport.Error.exhausted` on an unscripted call surfaces a test bug
/// (too few responses queued) as a clear failure instead of a hang or a
/// misleading crash.
actor MockTransport: TransmissionTransport {
    enum Error: Swift.Error {
        case exhausted
    }

    enum Scripted {
        case response(status: Int, headers: [String: String] = [:], body: Data = Data())
        case failure(any Swift.Error)
    }

    private var scripted: [Scripted]
    private(set) var requests: [URLRequest] = []

    init(_ scripted: [Scripted]) {
        self.scripted = scripted
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !scripted.isEmpty else { throw Error.exhausted }
        switch scripted.removeFirst() {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (body, response)
        case .failure(let error):
            throw error
        }
    }
}

private func success(_ body: String = #"{"result":"success"}"#) -> MockTransport.Scripted {
    .response(status: 200, body: Data(body.utf8))
}

@Suite("TransmissionClient")
struct TransmissionClientTests {
    let config = try! TransmissionConfig(host: "nas.local:9091", auth: "")

    @Test("successful torrent-add")
    func successfulTorrentAdd() async throws {
        let transport = MockTransport([success()])
        let client = TransmissionClient(transport: transport)
        try await client.addMagnet(uri: "magnet:?xt=urn:btih:\(String(repeating: "a", count: 40))", config: config)

        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url == config.rpcURL)
    }

    @Test("successful session-get")
    func successfulSessionGet() async throws {
        let transport = MockTransport([success()])
        let client = TransmissionClient(transport: transport)
        try await client.testConnection(config: config)

        let requests = await transport.requests
        #expect(requests.count == 1)
    }

    @Test("409 is retried with the refreshed session ID")
    func retriesOn409() async throws {
        let transport = MockTransport([
            .response(status: 409, headers: ["X-Transmission-Session-Id": "abc123"]),
            success(),
        ])
        let client = TransmissionClient(transport: transport)
        try await client.testConnection(config: config)

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "X-Transmission-Session-Id") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "X-Transmission-Session-Id") == "abc123")
    }

    @Test("409 with no session header still retries, without a session header")
    func retriesOn409WithMissingHeader() async throws {
        let transport = MockTransport([
            .response(status: 409),
            success(),
        ])
        let client = TransmissionClient(transport: transport)
        try await client.testConnection(config: config)

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "X-Transmission-Session-Id") == nil)
    }

    @Test("non-200 status throws with the status code and body")
    func nonTwoHundredThrows() async {
        let transport = MockTransport([
            .response(status: 500, body: Data("daemon on fire".utf8)),
        ])
        let client = TransmissionClient(transport: transport)
        await #expect(throws: TransmissionError.self) {
            try await client.testConnection(config: config)
        }
    }

    @Test("an authentication failure surfaces like any other non-200 status")
    func authenticationFailureThrows() async {
        let transport = MockTransport([.response(status: 401)])
        let client = TransmissionClient(transport: transport)
        await #expect(throws: TransmissionError.self) {
            try await client.testConnection(config: config)
        }
    }

    @Test("malformed JSON throws instead of decoding garbage")
    func malformedJSONThrows() async {
        let transport = MockTransport([
            .response(status: 200, body: Data("not json".utf8)),
        ])
        let client = TransmissionClient(transport: transport)
        await #expect(throws: TransmissionError.self) {
            try await client.testConnection(config: config)
        }
    }

    @Test("a result other than success throws")
    func nonSuccessResultThrows() async {
        let transport = MockTransport([success(#"{"result":"duplicate torrent"}"#)])
        let client = TransmissionClient(transport: transport)
        await #expect(throws: TransmissionError.self) {
            try await client.addMagnet(uri: "magnet:?xt=urn:btih:\(String(repeating: "a", count: 40))", config: config)
        }
    }

    @Test("a timeout is reported as a timeout, not a generic failure")
    func timeoutIsReportedDistinctly() async {
        let transport = MockTransport([.failure(URLError(.timedOut))])
        let client = TransmissionClient(transport: transport)
        do {
            try await client.testConnection(config: config)
            Issue.record("expected testConnection to throw")
        } catch {
            let message = (error as? TransmissionError)?.errorDescription ?? ""
            #expect(message.contains("timed out"))
        }
    }

    @Test("the magnet URI is sent verbatim as the torrent-add filename")
    func preservesMagnetURIInPayload() async throws {
        let transport = MockTransport([success()])
        let client = TransmissionClient(transport: transport)
        let uri = "magnet:?xt=urn:btih:\(String(repeating: "b", count: 40))&dn=Some+Name&tr=http%3A%2F%2Ftracker.example%2Fannounce"
        try await client.addMagnet(uri: uri, config: config)

        let requests = await transport.requests
        let body = try #require(requests[0].httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["method"] as? String == "torrent-add")
        let arguments = try #require(json["arguments"] as? [String: Any])
        #expect(arguments["filename"] as? String == uri)
    }
}
