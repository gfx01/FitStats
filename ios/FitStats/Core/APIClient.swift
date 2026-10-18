import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case server(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "This app is no longer authorised. Connect Google again."
        case .server(let code, let body):
            // Coach and setup errors carry a readable `message`; show that alone.
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["message"] as? String {
                return message
            }
            return "Server error \(code): \(body.prefix(200))"
        case .transport(let error):
            return "Network problem: \(error.localizedDescription)"
        case .decoding(let error):
            return "Unexpected server data: \(error.localizedDescription)"
        }
    }
}

extension Error {
    /// The app abandoned the request itself: a screen closed, a newer load replaced it, or a
    /// pull to refresh ended. Nothing failed, so it is never shown as an error.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let api = self as? APIError, case .transport(let inner) = api { return inner.isCancellation }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

struct APIClient {
    let baseURL: URL
    let key: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func url(base: URL, route: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "r", value: route)]
        for (k, v) in query.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        return components.url!
    }

    func raw(_ route: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: Self.url(base: baseURL, route: route, query: query))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else {
            throw APIError.server(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func fetch<T: Decodable>(_ type: T.Type, _ route: String, query: [String: String] = [:]) async throws -> (T, Data) {
        let data = try await raw(route, query: query)
        do {
            return (try JSONDecoder().decode(T.self, from: data), data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func post(_ route: String, query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        try await raw(route, method: "POST", query: query, body: body ?? Data("{}".utf8))
    }

    /// Replies can pause while Claude thinks or runs tools; the server sends keep-alives.
    private static let streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// POST that streams server-sent events (`data: {json}` lines) as they arrive.
    func events(_ route: String, body: Data) -> AsyncThrowingStream<CoachEvent, Error> {
        let request: URLRequest = {
            var r = URLRequest(url: Self.url(base: baseURL, route: route))
            r.httpMethod = "POST"
            r.httpBody = body
            r.setValue(key, forHTTPHeaderField: "x-app-key")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            return r
        }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.streamSession.bytes(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 401 { throw APIError.unauthorized }
                    guard (200..<300).contains(code) else {
                        var text = ""
                        for try await line in bytes.lines {
                            text += line
                            if text.count > 4000 { break }
                        }
                        throw APIError.server(code, text)
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let event = try? decoder.decode(CoachEvent.self, from: Data(payload.utf8)) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: APIError.transport(error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
