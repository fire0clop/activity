import SwiftUI

struct ChatsListView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var items: [ConversationListItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.paper.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Чаты").font(.display(34)).foregroundStyle(Theme.ink).padding(.top, 8)
                        if items.isEmpty && isLoading {
                            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 60)
                        } else if items.isEmpty {
                            emptyState
                        } else {
                            ForEach(items) { c in
                                NavigationLink {
                                    ChatView(conversationID: c.id, title: c.title ?? "Чат")
                                } label: { row(c) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .refreshable { await load() }
            }
            .navigationBarHidden(true)
            .task { await load() }
        }
    }

    private func row(_ c: ConversationListItem) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarCircle(url: c.avatarURL, name: c.title, size: 52)
                if c.type == "event" {
                    Image(systemName: "calendar.circle.fill").font(.system(size: 17))
                        .foregroundStyle(Theme.accent, Theme.surface)
                        .offset(x: 3, y: 3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title ?? "Чат").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if let last = c.lastMessage {
                    Text(last.senderName != nil ? "\(last.senderName!): \(last.text)" : last.text)
                        .font(.system(size: 14)).foregroundStyle(Theme.ink2).lineLimit(1)
                } else {
                    Text("Нет сообщений").font(.system(size: 14)).foregroundStyle(Theme.ink2.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let last = c.lastMessage {
                    Text(DateFormat.time(last.createdAt)).font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                if c.unreadCount > 0 {
                    Text("\(c.unreadCount)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22).padding(.horizontal, 4)
                        .background(Theme.accent).clipShape(Capsule())
                }
            }
        }
        .padding(12).cardStyle()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 96, height: 96)
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
            }
            Text("Пока пусто").font(.serifTitle(22, weight: .bold)).foregroundStyle(Theme.ink)
            Text("Чат события откроется,\nкогда тебя примут или к тебе придут.")
                .font(.subheadline).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let resp: ConversationListResponse? = try? await auth.api.send(Endpoint(path: "/conversations"))
        items = resp?.items ?? []
    }
}
