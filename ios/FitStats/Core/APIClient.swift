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
            return "Server error \(code): \(body.prefix(200))"
        case .transport(let error):
            return "Network problem: \(error.localizedDescription)"
        case .decoding(let error):
            return "Unexpected server data: \(error.localizedDescription)"
        }
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
}
