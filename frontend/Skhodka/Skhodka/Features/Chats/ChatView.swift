import SwiftUI

/// Живой чат через WebSocket (история + новые сообщения + отправка).
struct ChatView: View {
    let conversationID: String
    let title: String
    var isArchived: Bool = false
    var isGroup: Bool = false
    @EnvironmentObject var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ws = WebSocketClient()
    @State private var draft = ""
    @State private var historyError: String?

    private var canSend: Bool {
        ws.connected && !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if let historyError, ws.messages.isEmpty {
                            Text(historyError).font(.footnote).foregroundStyle(Theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
                        }
                        ForEach(Array(ws.messages.enumerated()), id: \.element.id) { index, m in
                            row(m, prev: index > 0 ? ws.messages[index - 1] : nil).id(m.id)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .onChange(of: ws.messages.count) { _, _ in
                    if let last = ws.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    Circle().fill(ws.connected ? Theme.accent : Theme.line)
                        .frame(width: 9, height: 9)
                        .accessibilityLabel(ws.connected ? "В сети" : "Нет соединения")
                    if isGroup {
                        NavigationLink { GroupInfoView(conversationID: conversationID) } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("О группе")
                    }
                }
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

    @ViewBuilder
    private var inputBar: some View {
        if isArchived {
            Label("Событие завершено — беседа в архиве", systemImage: "archivebox")
                .font(.footnote).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity).padding(14)
                .background(Theme.paper)
        } else {
            HStack(spacing: 8) {
                TextField("Написать сообщение…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line))
                Button {
                    if ws.send(text: draft) { draft = ""; Haptics.tap() }
                } label: {
                    Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(canSend ? Theme.accent : Theme.line)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Отправить сообщение")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.paper)
            .overlay(Divider(), alignment: .top)
        }
    }

    /// Пауза перед REST-фолбэком истории, если WebSocket не успел прислать history.
    private static let historyFallbackDelayNs: UInt64 = 1_500_000_000

    /// Подстраховка: если WS не поднялся и history не пришла — тянем её по REST.
    private func loadHistoryFallback() async {
        try? await Task.sleep(nanoseconds: Self.historyFallbackDelayNs)
        guard ws.messages.isEmpty, !Task.isCancelled else { return }
        do {
            let resp: MessagesResponse = try await auth.api.send(
                Endpoint(path: "/conversations/\(conversationID)/messages"))
            // REST отдаёт newest-first; на экране — старые сверху.
            ws.applyRESTHistory(resp.items.reversed())
        } catch {
            if ws.messages.isEmpty { historyError = "Не удалось загрузить историю. Проверьте соединение." }
        }
    }

    @ViewBuilder
    private func row(_ m: Message, prev: Message?) -> some View {
        if m.isSystem {
            Text(m.text).font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.surface).clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else {
            let mine = m.sender?.id == auth.me?.id
            // Новая «группа», когда сменился автор или до этого было системное сообщение.
            let startsGroup = prev == nil || prev!.isSystem || prev!.sender?.id != m.sender?.id
            if mine {
                outgoing(m).padding(.top, startsGroup ? 6 : 0)
            } else {
                incoming(m, showHeader: startsGroup).padding(.top, startsGroup ? 6 : 0)
            }
        }
    }

    private func outgoing(_ m: Message) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(m.text)
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Theme.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.22)))
        }
    }

    private func incoming(_ m: Message, showHeader: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Колонка аватара фиксированной ширины — сгруппированные сообщения выравниваются.
            Group {
                if showHeader {
                    AvatarCircle(url: m.sender?.avatarURL, name: m.sender?.name, size: 30)
                } else {
                    Color.clear.frame(width: 30, height: 1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if showHeader, let name = m.sender?.name {
                    Text(name).font(.caption2).foregroundStyle(Theme.ink2).padding(.leading, 2)
                }
                Text(m.text)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            }
            Spacer(minLength: 40)
        }
    }
}
