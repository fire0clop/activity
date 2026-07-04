import SwiftUI

/// Живой чат через WebSocket (история + новые сообщения + отправка).
struct ChatView: View {
    let conversationID: String
    let title: String
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ws = WebSocketClient()
    @State private var draft = ""
    @State private var historyError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let historyError, ws.messages.isEmpty {
                            Text(historyError).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
                        }
                        ForEach(ws.messages) { m in bubble(m).id(m.id) }
                    }
                    .padding()
                }
                .onChange(of: ws.messages.count) { _, _ in
                    if let last = ws.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack {
                TextField("Сообщение…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                Button {
                    ws.send(text: draft)
                    draft = ""
                } label: { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Circle().fill(ws.connected ? .green : .gray).frame(width: 9, height: 9)
            }
        }
        .onAppear {
            ws.connect(conversationID: conversationID) { [weak auth] in
                await auth?.api.validAccessToken()
            }
        }
        .task { await loadHistoryFallback() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ws.ensureConnected() }
        }
        .onDisappear { ws.disconnect() }
    }

    /// Подстраховка: если WS не поднялся и history не пришла — тянем её по REST.
    private func loadHistoryFallback() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard ws.messages.isEmpty, !Task.isCancelled else { return }
        do {
            let resp: MessagesResponse = try await auth.api.send(
                Endpoint(path: "/conversations/\(conversationID)/messages"))
            // REST отдаёт newest-first; на экране — старые сверху.
            if ws.messages.isEmpty { ws.messages = resp.items.reversed() }
        } catch {
            if ws.messages.isEmpty { historyError = "Не удалось загрузить историю. Проверьте соединение." }
        }
    }

    @ViewBuilder
    private func bubble(_ m: Message) -> some View {
        if m.isSystem {
            Text(m.text).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            let mine = m.sender?.id == auth.me?.id
            HStack {
                if mine { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    if !mine, let name = m.sender?.name {
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(m.text)
                }
                .padding(10)
                .background(mine ? Theme.accent.opacity(0.85) : Theme.secondaryBg)
                .foregroundStyle(mine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                if !mine { Spacer(minLength: 40) }
            }
        }
    }
}
