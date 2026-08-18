import Foundation

/// Машиночитаемые коды ошибок бэка (backend §11, app/core/exceptions.py).
enum APIErrorCode: String {
    // Auth / сессия
    case unauthorized
    case invalidCredentials = "invalid_credentials"
    case alreadyRegistered = "already_registered"
    case invalidCode = "invalid_code"
    case codeExpired = "code_expired"
    case tooManyAttempts = "too_many_attempts"
    case smsSendFailed = "sms_send_failed"
    case rateLimited = "rate_limited"
    // Доступ
    case forbidden
    case profileIncomplete = "profile_incomplete"
    case notFound = "not_found"
    // События / заявки / отзывы
    case alreadyJoined = "already_joined"
    case eventFull = "event_full"
    case eventClosed = "event_closed"
    case alreadyReviewed = "already_reviewed"
    // Общие
    case validationError = "validation_error"
    case httpError = "http_error"
}

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

    /// Типизированный код; nil — код бэка не из известного списка (или локальная ошибка).
    var errorCode: APIErrorCode? { APIErrorCode(rawValue: error.code) }

    func isCode(_ code: APIErrorCode) -> Bool { errorCode == code }

    private enum CodingKeys: String, CodingKey { case error }

    /// Локальная (не серверная) ошибка — сеть, декодинг и т.п.
    static func local(_ message: String, code: String = "client_error") -> APIError {
        APIError(error: Body(code: code, message: message), status: 0)
    }
}
