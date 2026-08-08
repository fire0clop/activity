import SwiftUI

/// Знакомые — те, с кем уже была общая встреча.
///
/// Это не каталог людей: список нельзя пополнить поиском, он растёт только от
/// завершённых событий. Поэтому здесь же открывается личная переписка — право на
/// неё даёт факт встречи, а не кнопка «написать незнакомцу».
struct ConnectionsView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var items: [Connection] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorText: String?
    @State private var openingChat: String?
    @State private var chatRoute: ChatRoute?

    private struct ChatRoute: Identifiable, Hashable {
        let id: String
        let title: String
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                }
                if isLoading && items.isEmpty {
                    ProgressView().tint(Theme.accent).padding(.top, 40)
                } else if loadFailed {
                    ErrorState { Task { await load() } }
                } else if items.isEmpty {
                    EmptyState(
                        icon: "person.2",
                        title: "Здесь появятся свои",
                        subtitle: "Сходите на встречу — и её участники окажутся в этом списке. Им можно будет написать лично и позвать в свои события."
                    )
                } else {
                    ForEach(items) { row($0) }
                    Text("Список растёт только от встреч — искать людей в приложении нельзя.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Знакомые")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $chatRoute) { route in
            ChatView(conversationID: route.id, title: route.title)
        }
    }

    private func row(_ c: Connection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { PublicProfileView(userID: c.user.id) } label: {
                HStack(spacing: 12) {
                    AvatarCircle(url: c.user.avatarURL, name: c.user.name, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(c.user.name ?? "Знакомый")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            if c.mutual {
                                Text("свои")
                                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(Theme.accentInk)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accentSoft, in: Capsule())
                            }
                        }
                        RatingView(value: c.user.ratingAvg, count: c.user.ratingCount)
                        Text(meetingsLine(c))
                            .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button { Task { await openChat(with: c) } } label: {
                    HStack(spacing: 6) {
                        if openingChat == c.user.id {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bubble.left.fill").font(.system(size: 12, weight: .bold))
                        }
                        Text("Написать").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radii.sm))
                }
                .disabled(openingChat != nil)

                Button { Task { await toggleFollow(c) } } label: {
                    Text(c.iFollow ? "Не следить" : "Следить за событиями")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Theme.secondaryBg, in: RoundedRectangle(cornerRadius: Radii.sm))
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    private func meetingsLine(_ c: Connection) -> String {
        let times = switch c.meetings {
        case 1: "виделись однажды"
        default: "виделись \(c.meetings) раза"
        }
        return "\(times) · «\(c.lastEventTitle)»"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: ConnectionsResponse = try await auth.api.send(
                Endpoint(path: "/connections"))
            items = resp.items
            errorText = nil; loadFailed = false
        } catch let err as APIError {
            errorText = err.message; loadFailed = items.isEmpty
        } catch {
            loadFailed = items.isEmpty
        }
    }

    private func openChat(with c: Connection) async {
        errorText = nil
        openingChat = c.user.id
        defer { openingChat = nil }
        do {
            let resp: DirectChatResponse = try await auth.api.send(Endpoint(
                path: "/connections/\(c.user.id)/chat", method: .post))
            chatRoute = ChatRoute(id: resp.conversationID, title: c.user.name ?? "Переписка")
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось открыть переписку. Попробуйте ещё раз." }
    }

    private func toggleFollow(_ c: Connection) async {
        errorText = nil
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/users/\(c.user.id)/follow", method: c.iFollow ? .delete : .post))
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось изменить подписку." }
    }
}

/// Выбор знакомых, которых организатор зовёт в своё событие.
///
/// Позвать можно только тех, с кем уже виделись, и приглашённый подтверждает участие
/// сам — молча добавлять людей в чужую встречу и её чат нельзя.
struct InviteConnectionsView: View {
    let eventID: String
    var onDone: (Int) -> Void = { _ in }

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Connection] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    if isLoading {
                        ProgressView().tint(Theme.accent).padding(.top, 40)
                    } else if items.isEmpty {
                        EmptyState(
                            icon: "person.2",
                            title: "Пока некого звать",
                            subtitle: "Звать можно тех, с кем уже была общая встреча."
                        )
                    } else {
                        ForEach(items) { c in
                            Button {
                                if selected.contains(c.user.id) { selected.remove(c.user.id) }
                                else { selected.insert(c.user.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarCircle(url: c.user.avatarURL, name: c.user.name, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.user.name ?? "Знакомый")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("виделись \(c.meetings)×")
                                            .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(c.user.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selected.contains(c.user.id)
                                                         ? Theme.accent : Theme.line)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle()
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Приглашённый получит уведомление и решит сам — в состав его никто не добавляет молча.")
                            .font(.footnote).foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.top, 6)
                    }
                }
                .padding(16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Позвать своих")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSending ? "…" : "Позвать") { Task { await invite() } }
                        .disabled(selected.isEmpty || isSending)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let resp: ConnectionsResponse? = try? await auth.api.send(Endpoint(path: "/connections"))
        items = resp?.items ?? []
    }

    private func invite() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            let resp: InviteResponse = try await auth.api.send(Endpoint(
                path: "/events/\(eventID)/invite", method: .post,
                body: InviteBody(user_ids: Array(selected))))
            Haptics.success()
            onDone(resp.invited)
            dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось отправить приглашения." }
    }
}
