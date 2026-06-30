import Foundation

/// Ответ /auth/verify-code и /auth/refresh (backend §9.2).
struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let isNewUser: Bool?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case isNewUser = "is_new_user"
    }
}

struct RequestCodeResponse: Decodable {
    let sent: Bool
    let resendAfterSec: Int
    private enum CodingKeys: String, CodingKey {
        case sent
        case resendAfterSec = "resend_after_sec"
    }
}

// Тела запросов.
struct PhoneBody: Encodable { let phone: String }
struct RegisterBody: Encodable { let phone: String; let code: String; let password: String }
struct LoginBody: Encodable { let phone: String; let password: String }
struct ResetPasswordBody: Encodable { let phone: String; let code: String; let new_password: String }
struct RefreshBody: Encodable { let refresh_token: String }
