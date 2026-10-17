import Foundation
import Testing
@testable import Folio

/// Answers requests from a handler registered per session (header `X-Stub-ID`), so suites can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var seenByID: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub-ID") ?? ""
        Self.lock.lock()
        Self.seenByID[id, default: []].append(request)
        let handler = Self.handlers[id]
        Self.lock.unlock()
        do {
            guard let (status, data) = try handler?(request), let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    /// Requests seen by the client created with this id's handler.
    static func seen(_ client: OllamaClient) -> [URLRequest] {
        let id = client.session.configuration.httpAdditionalHeaders?["X-Stub-ID"] as? String ?? ""
        lock.lock(); defer { lock.unlock() }
        return seenByID[id] ?? []
    }

    static func client(_ handler: @escaping Handler) -> OllamaClient {
        let id = UUID().uuidString
        lock.lock(); handlers[id] = handler; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub-ID": id]
        return OllamaClient(session: URLSession(configuration: config))
    }

    /// Replaces the answer of an existing client (to simulate Ollama coming back).
    static func replace(_ client: OllamaClient, with handler: @escaping Handler) {
        let id = client.session.configuration.httpAdditionalHeaders?["X-Stub-ID"] as? String ?? ""
        lock.lock(); handlers[id] = handler; lock.unlock()
    }
}

struct OllamaClientTests {
    struct Answer: Decodable, Sendable, Equatable { let name: String; let confidence: Double }
    private let schema = #"{"type":"object","properties":{"name":{"type":"string"},"confidence":{"type":"number"}},"required":["name","confidence"]}"#

    private func chatBody(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
    }

    @Test func chatDecodesStructuredReplyAndSendsExpectedRequest() async throws {
        let client = StubURLProtocol.client { _ in (200, try self.chatBody(#"{"name":"Invoice","confidence":0.9}"#)) }
        let answer = try await client.chat(.autonomous, system: "sys", user: "usr", schema: schema, as: Answer.self)
        #expect(answer == Answer(name: "Invoice", confidence: 0.9))
        let request = try #require(StubURLProtocol.seen(client).first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        #expect(request.timeoutInterval == 180)
        let bodyData = try #require(request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        })
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["model"] as? String == "gemma4:12b")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect(body["keep_alive"] as? String == "10m")
        #expect(body["format"] is [String: Any])
    }

    @Test func offlineMapsConnectionErrors() async {
        let client = StubURLProtocol.client { _ in throw URLError(.cannotConnectToHost) }
        await #expect(throws: OllamaError.offline) { try await client.chat(.autonomous, system: "", user: "", schema: schema, as: Answer.self) }
        #expect(await client.isReachable() == false)
    }

    @Test func timeoutIsDistinctFromOffline() async {
        let client = StubURLProtocol.client { _ in throw URLError(.timedOut) }
        await #expect(throws: OllamaError.timeout) { try await client.embed(input: "x") }
    }

    @Test func missingModelIs404() async {
        let client = StubURLProtocol.client { _ in (404, Data(#"{"error":"model not found"}"#.utf8)) }
        await #expect(throws: OllamaError.modelMissing("gemma4:12b")) { try await client.chat(.restructure, system: "", user: "", schema: schema, as: Answer.self) }
    }

    @Test func malformedReplyIsBadResponseNotACrash() async {
        let notJSON = StubURLProtocol.client { _ in (200, Data("<html>".utf8)) }
        await #expect(throws: OllamaError.badResponse) { try await notJSON.chat(.autonomous, system: "", user: "", schema: schema, as: Answer.self) }
        let wrongShape = StubURLProtocol.client { _ in (200, try self.chatBody(#"{"unexpected":true}"#)) }
        await #expect(throws: OllamaError.badResponse) { try await wrongShape.chat(.autonomous, system: "", user: "", schema: schema, as: Answer.self) }
        let serverError = StubURLProtocol.client { _ in (500, Data()) }
        await #expect(throws: OllamaError.badResponse) { try await serverError.embed(input: "x") }
        await #expect(throws: OllamaError.badResponse) { try await notJSON.chat(.autonomous, system: "", user: "", schema: "{not json", as: Answer.self) }
    }

    @Test func embedAndModelListing() async throws {
        let client = StubURLProtocol.client { request in
            if request.url?.path == "/api/embed" { return (200, Data(#"{"embeddings":[[0.5,0.25]]}"#.utf8)) }
            return (200, Data(#"{"models":[{"name":"gemma4:e2b"},{"name":"mxbai-embed-large:latest"}]}"#.utf8))
        }
        #expect(try await client.embed(input: "hi") == [0.5, 0.25])
        #expect(try await client.hasModel("gemma4:e2b"))
        #expect(try await client.hasModel("mxbai-embed-large"))
        #expect(try await !client.hasModel("gemma4:12b"))
    }

    @Test func everyRequestStaysOnLoopback() async throws {
        let client = StubURLProtocol.client { _ in (200, Data(#"{"models":[]}"#.utf8)) }
        _ = try await client.hasModel("x")
        _ = await client.isReachable()
        #expect(StubURLProtocol.seen(client).allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 11434 })
    }
}
