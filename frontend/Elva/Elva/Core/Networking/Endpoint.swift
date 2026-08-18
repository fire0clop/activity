import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Описание запроса к API.
struct Endpoint {
    var path: String                      // относительный, напр. "/auth/verify-code"
    var method: HTTPMethod = .get
    var query: [String: String?] = [:]
    var body: Encodable? = nil
    var requiresAuth: Bool = true

    func url(base: URL) -> URL {
        var comps = URLComponents(
            url: base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )!
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url!
    }
}
