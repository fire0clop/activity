import Foundation

/// Живой чат через WebSocket (backend §10). Один экземпляр на открытую беседу.
///
/// Изолирован `@MainActor`: `task`/`connected`/`intentionalClose`/`messages` больше не
/// мутируются из фоновых URLSession-колбэков напрямую — все переходы идут через главный
/// актор, что исключает гонки и «залипший» connected при обрыве/возврате из фона.
@MainActor
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
    /// id уже показанных сообщений — защита от дублей (history + WS + reconnect).
    private var messageIDs: Set<String> = []

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
        Task { await openSocket() }
    }

    private func openSocket() async {
        guard let token = await tokenProvider() else {
            connected = false
            return
        }
        // Не плодим сокеты: гасим предыдущий перед созданием нового.
        task?.cancel(with: .goingAway, reason: nil)

        let url = AppConfig.wsBaseURL.appendingPathComponent("ws/chat/\(conversationID)")
        // Токен передаём через Sec-WebSocket-Protocol ("bearer, <jwt>"), а не в query —
        // так он не утекает в access-логи reverse-proxy. Сервер эхом выбирает "bearer".
        let socket = URLSession.shared.webSocketTask(with: url, protocols: ["bearer", token])
        task = socket
        socket.resume()
        receive(on: socket)
    }

    /// Ставит сообщение в отправку. Возвращает false, если сокет не готов или текст не
    /// сериализовался — тогда вызывающий НЕ должен очищать поле ввода (иначе текст теряется).
    @discardableResult
    func send(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let payload = ["type": "message", "text": trimmed]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return false }
        guard let task, connected else { return false }
        task.send(.string(str)) { _ in }
        return true
    }

    func disconnect() {
        intentionalClose = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// История, догруженная по REST (fallback, если WS не поднялся). Заполняет и id-набор,
    /// чтобы последующие WS-сообщения не задваивались.
    func applyRESTHistory(_ items: [Message]) {
        guard messages.isEmpty else { return }
        messages = items
        messageIDs = Set(items.map { $0.id })
    }

    /// Привязываем чтение к КОНКРЕТНОМУ сокету: колбэки уже заменённого соединения
    /// игнорируются (`self.task === socket`), иначе обрыв старого сокета инициировал бы
    /// лишний reconnect поверх актуального — источник двойных сокетов и задвоенных сообщений.
    private nonisolated func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === socket else { return }
                switch result {
                case .success(let msg):
                    // Сервер сразу шлёт history — первый кадр и означает «подключены».
                    if !self.connected { self.connected = true }
                    if case .string(let text) = msg { self.handle(text) }
                    self.receive(on: socket)
                case .failure:
                    self.connected = false
                    self.reconnectIfNeeded()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? decoder.decode(Envelope.self, from: data) else { return }
        switch env.type {
        case "history":
            let msgs = env.messages ?? []
            messages = msgs
            messageIDs = Set(msgs.map { $0.id })
        case "message", "system":
            if let m = env.message, !messageIDs.contains(m.id) {
                messageIDs.insert(m.id)
                messages.append(m)
            }
        case "presence":
            onlineCount = env.onlineUserIds?.count ?? 0
        default:
            break
        }
    }

    private func reconnectIfNeeded() {
        guard !intentionalClose, !connected else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !self.intentionalClose, !self.connected else { return }
            await self.openSocket()
        }
    }
}
