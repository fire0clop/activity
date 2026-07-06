import Foundation

/// Живой чат через WebSocket (backend §10). Один экземпляр на открытую беседу.
final class WebSocketClient: NSObject, ObservableObject {
    @Published var messages: [Message] = []
    @Published var onlineCount = 0
    @Published var connected = false

    private var task: URLSessionWebSocketTask?
    private var conversationID = ""
    /// Отдаёт свежий access-токен (с refresh при необходимости) перед каждым коннектом.
    private var tokenProvider: () async -> String? = { nil }
    private var intentionalClose = false
    private let decoder = JSONDecoder()

    private struct Envelope: Decodable {
        let type: String
        let messages: [Message]?
        let message: Message?
        let onlineUserIds: [String]?
        private enum CodingKeys: String, CodingKey {
            case type, messages, message
            case onlineUserIds = "online_user_ids"
        }
    }

    func connect(conversationID: String, tokenProvider: @escaping () async -> String?) {
        self.conversationID = conversationID
        self.tokenProvider = tokenProvider
        intentionalClose = false
        Task { await openSocket() }
    }

    /// Переоткрывает сокет, если он не активен (обрыв, возврат приложения из фона).
    func ensureConnected() {
        guard !intentionalClose, !connected else { return }
        task?.cancel(with: .goingAway, reason: nil)
        Task { await openSocket() }
    }

    private func openSocket() async {
        guard let token = await tokenProvider() else {
            await MainActor.run { self.connected = false }
            return
        }
        let url = AppConfig.wsBaseURL
            .appendingPathComponent("ws/chat/\(conversationID)")
        // Токен передаём через Sec-WebSocket-Protocol ("bearer, <jwt>"), а не в query —
        // так он не утекает в access-логи reverse-proxy. Сервер эхом выбирает "bearer".
        let task = URLSession.shared.webSocketTask(with: url, protocols: ["bearer", token])
        self.task = task
        task.resume()
        receive()
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload = ["type": "message", "text": trimmed]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    func disconnect() {
        intentionalClose = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                // Сервер сразу шлёт history — первый кадр и означает «подключены».
                DispatchQueue.main.async { if !self.connected { self.connected = true } }
                if case .string(let text) = msg { self.handle(text) }
                self.receive()
            case .failure:
                DispatchQueue.main.async { self.connected = false }
                self.reconnectIfNeeded()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? decoder.decode(Envelope.self, from: data) else { return }
        DispatchQueue.main.async {
            switch env.type {
            case "history":
                self.messages = env.messages ?? []
            case "message", "system":
                if let m = env.message { self.messages.append(m) }
            case "presence":
                self.onlineCount = env.onlineUserIds?.count ?? 0
            default:
                break
            }
        }
    }

    private func reconnectIfNeeded() {
        guard !intentionalClose else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !self.intentionalClose else { return }
            await self.openSocket()
        }
    }
}
