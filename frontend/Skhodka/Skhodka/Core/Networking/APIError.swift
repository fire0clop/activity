import Foundation

/// Ошибка API в формате бэка: { "error": { "code", "message", "details } } (backend §11).
struct APIError: Error, Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }
    let error: Body
    var status: Int = 0

    var code: String { error.code }
    var message: String { error.message }

    private enum CodingKeys: String, CodingKey { case error }

    /// Локальная (не серверная) ошибка — сеть, декодинг и т.п.
    static func local(_ message: String, code: String = "client_error") -> APIError {
        APIError(error: Body(code: code, message: message), status: 0)
    }
}
