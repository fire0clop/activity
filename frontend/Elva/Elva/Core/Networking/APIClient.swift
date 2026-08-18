import Foundation

/// Async HTTP-клиент. Добавляет Bearer-токен, при 401 один раз пытается обновить токен.
final class APIClient {
    private let base: URL
    private let tokenStore: TokenStore
    private let session: URLSession

    /// Вызывается, когда сессия окончательно невалидна (refresh не удался).
    var onUnauthorized: (() -> Void)?

    /// Вызывается на 403 profile_incomplete — профиль не заполнен, нужен онбординг.
    var onProfileIncomplete: (() -> Void)?

    init(base: URL = AppConfig.baseURL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.base = base
        self.tokenStore = tokenStore
        self.session = session
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    // MARK: - Public

    @discardableResult
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let data = try await rawSend(endpoint, retryOn401: true)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.local("Не удалось обработать ответ сервера", code: "decode_error")
        }
    }

    /// Для запросов без тела ответа (204).
    func sendVoid(_ endpoint: Endpoint) async throws {
        _ = try await rawSend(endpoint, retryOn401: true)
    }

    /// Загрузка файла (multipart) — для аватара/обложки.
    func upload<T: Decodable>(path: String, fileData: Data, fileName: String,
                              mimeType: String, field: String = "file") async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        try checkStatusIntercepting(data: data, resp: resp)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Best-effort уведомление бэка о выходе: отвязать устройство и погасить refresh-токен.
    /// Использует ЗАХВАЧЕННЫЕ токены (не читает tokenStore) и не участвует в refresh —
    /// чтобы не затронуть возможный новый вход, начавшийся сразу после signOut.
    func bestEffortSignOut(refresh: String?, accessToken: String?, deviceToken: String?) async {
        if let deviceToken, let accessToken,
           let encoded = deviceToken.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            var req = URLRequest(url: base.appendingPathComponent("devices/\(encoded)"))
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: req)
        }
        if let refresh {
            var req = URLRequest(url: base.appendingPathComponent("auth/logout"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(["refresh_token": refresh])
            _ = try? await session.data(for: req)
        }
    }

    // MARK: - Internal

    private func rawSend(_ endpoint: Endpoint, retryOn401: Bool) async throws -> Data {
        let request = try makeRequest(endpoint)
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.local("Нет ответа от сервера", code: "no_response")
        }

        if http.statusCode == 401, endpoint.requiresAuth, retryOn401 {
            if await refresh() {
                return try await rawSend(endpoint, retryOn401: false)
            } else {
                onUnauthorized?()
                throw APIError.local("Сессия истекла", code: "unauthorized")
            }
        }
        try checkStatusIntercepting(data: data, resp: resp)
        return data
    }

    /// Проверка статуса + глобальные перехваты (profile_incomplete → онбординг).
    private func checkStatusIntercepting(data: Data, resp: URLResponse) throws {
        do {
            try Self.checkStatus(data: data, resp: resp)
        } catch let err as APIError {
            if err.status == 403, err.isCode(.profileIncomplete) {
                onProfileIncomplete?()
            }
            throw err
        }
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        var req = URLRequest(url: endpoint.url(base: base))
        req.httpMethod = endpoint.method.rawValue
        if endpoint.requiresAuth, let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(AnyEncodable(body))
        }
        return req
    }

    private static func checkStatus(data: Data, resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.local("Нет ответа от сервера", code: "no_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if var apiErr = try? decoder.decode(APIError.self, from: data) {
                apiErr.status = http.statusCode
                throw apiErr
            }
            throw APIError.local("Ошибка сервера (\(http.statusCode))", code: "http_\(http.statusCode)")
        }
    }

    /// Актуальный access-токен (для WebSocket): если текущий истёк или вот-вот
    /// истечёт — сначала обновляет пару через /auth/refresh.
    func validAccessToken() async -> String? {
        if let token = tokenStore.accessToken, !Self.isExpiringSoon(token) { return token }
        return await refresh() ? tokenStore.accessToken : nil
    }

    /// Читает exp из payload JWT без проверки подписи — только чтобы решить, пора ли обновлять.
    private static func isExpiringSoon(_ jwt: String, leeway: TimeInterval = 30) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return false }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < leeway
    }

    /// Сериализует конкурентные обновления токена: при нескольких параллельных 401
    /// (типичный холодный старт — лента + чаты + профиль) все ждут ОДИН in-flight refresh.
    /// Иначе повторная ротация одноразового refresh-токена на бэке разлогинивает пользователя.
    private actor RefreshCoordinator {
        private var inFlight: Task<Bool, Never>?
        func run(_ operation: @escaping () async -> Bool) async -> Bool {
            if let task = inFlight { return await task.value }
            let task = Task { await operation() }
            inFlight = task
            let result = await task.value
            inFlight = nil
            return result
        }
    }

    private let refreshCoordinator = RefreshCoordinator()

    /// Обновление токена (дедуплицируется через RefreshCoordinator). true — успех.
    private func refresh() async -> Bool {
        await refreshCoordinator.run { [weak self] in
            await self?.performRefresh() ?? false
        }
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken = tokenStore.refreshToken else { return false }
        var req = URLRequest(url: base.appendingPathComponent("auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let pair = try? Self.decoder.decode(TokenPair.self, from: data) else {
            return false
        }
        tokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
        return true
    }
}

/// Обёртка, чтобы кодировать `Encodable` без дженерик-типа на уровне Endpoint.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
