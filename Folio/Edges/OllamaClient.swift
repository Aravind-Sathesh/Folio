import Foundation

enum OllamaError: Error, Equatable, Sendable {
    case offline
    case modelMissing(String)
    case badResponse
    case timeout
    case forbiddenHost
}

struct ModelSpec: Sendable, Equatable {
    let name: String
    let timeout: TimeInterval
    /// Short, so Ollama frees the model's memory soon after the last file.
    let keepAlive: String
    /// Thinking adds ~11 s per call on e2b (measured) and the JSON schema already constrains the answer, so it is off.
    var think = false

    // 12b chosen for filing (Oct 17): 98% correct vs 68% for e2b on the test set, 7 s a file. See docs/eval.md.
    // Kept loaded 10 minutes so a burst of downloads doesn't pay the ~12 s load each time.
    static let autonomous = ModelSpec(name: "gemma4:12b", timeout: 180, keepAlive: "10m")
    /// The smaller model, kept for the eval comparisons.
    static let small = ModelSpec(name: "gemma4:e2b", timeout: 60, keepAlive: "10m")
    static let restructure = ModelSpec(name: "gemma4:12b", timeout: 180, keepAlive: "2m")
    static let embedding = ModelSpec(name: "mxbai-embed-large", timeout: 30, keepAlive: "5m")
}

/// Talks to Ollama on this Mac and nowhere else. The host is checked on every request.
struct OllamaClient: Sendable {
    // The privacy invariant: the only network traffic Folio makes.
    private static let host = "127.0.0.1"
    private static let port = 11434

    var session: URLSession = .shared

    /// Constrained JSON chat. `schema` is a JSON Schema document as a string; the reply is decoded as `T`.
    func chat<T: Decodable & Sendable>(_ model: ModelSpec, system: String, user: String, schema: String, as type: T.Type = T.self) async throws -> T {
        guard let format = try? JSONSerialization.jsonObject(with: Data(schema.utf8)) else { throw OllamaError.badResponse }
        let body: [String: Any] = [
            "model": model.name,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "stream": false,
            "think": model.think,
            "format": format,
            "keep_alive": model.keepAlive,
            "options": ["temperature": 0], // same file, same answer
        ]
        let data = try await post("/api/chat", body: body, model: model)
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data),
              let value = try? JSONDecoder().decode(T.self, from: Data(reply.message.content.utf8)) else { throw OllamaError.badResponse }
        return value
    }

    func embed(_ model: ModelSpec = .embedding, input: String) async throws -> [Float] {
        let data = try await post("/api/embed", body: ["model": model.name, "input": input, "keep_alive": model.keepAlive], model: model)
        guard let reply = try? JSONDecoder().decode(EmbedReply.self, from: data), let vector = reply.embeddings.first, !vector.isEmpty
        else { throw OllamaError.badResponse }
        return vector
    }

    func isReachable() async -> Bool {
        (try? await get("/api/version", timeout: 3)) != nil
    }

    func hasModel(_ name: String) async throws -> Bool {
        let data = try await get("/api/tags", timeout: 5)
        guard let tags = try? JSONDecoder().decode(TagsReply.self, from: data) else { throw OllamaError.badResponse }
        return tags.models.contains { $0.name == name || $0.name == name + ":latest" }
    }

    // MARK: transport

    private struct ChatReply: Decodable { struct Message: Decodable { let content: String }; let message: Message }
    private struct EmbedReply: Decodable { let embeddings: [[Float]] }
    private struct TagsReply: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }

    private func url(_ path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = Self.host
        parts.port = Self.port
        parts.path = path
        return parts.url
    }

    private func get(_ path: String, timeout: TimeInterval) async throws -> Data {
        guard let url = url(path) else { throw OllamaError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await send(request, model: nil)
    }

    private func post(_ path: String, body: [String: Any], model: ModelSpec) async throws -> Data {
        guard let url = url(path), let payload = try? JSONSerialization.data(withJSONObject: body) else { throw OllamaError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = model.timeout
        return try await send(request, model: model.name)
    }

    private func send(_ request: URLRequest, model: String?) async throws -> Data {
        guard request.url?.host == Self.host, request.url?.port == Self.port else { throw OllamaError.forbiddenHost }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
            switch http.statusCode {
            case 200..<300: return data
            case 404 where model != nil: throw OllamaError.modelMissing(model ?? "")
            default: throw OllamaError.badResponse
            }
        } catch let error as OllamaError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() } // the caller gave up; that isn't "offline"
            throw error.code == .timedOut ? OllamaError.timeout : OllamaError.offline
        } catch {
            throw OllamaError.badResponse
        }
    }
}
