import SwiftUI

/// Карточка группы (V2): состав, переименование, управление участниками, выход.
struct GroupInfoView: View {
    let conversationID: String
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ConversationDetail?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showRename = false
    @State private var newTitle = ""
    @State private var showAddMembers = false
    @State private var showLeaveConfirm = false
    @State private var left = false

    var body: some View {
        List {
            if let d = detail {
                content(d)
            } else if isLoading {
                ProgressView()
            } else {
                Text(errorText ?? "Не удалось загрузить").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(detail?.title ?? "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Название группы", isPresented: $showRename) {
            TextField("Название", text: $newTitle)
            Button("Сохранить") { Task { await rename() } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Выйти из группы?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await leave() } }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $showAddMembers) {
            AddMembersSheet(conversationID: conversationID,
                            existingIDs: Set(detail?.members.map(\.id) ?? [])) {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func content(_ d: ConversationDetail) -> some View {
        Section {
            HStack(spacing: 12) {
                AvatarCircle(url: d.avatarURL, name: d.title, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title ?? "Группа").font(.headline)
                    Text("Участников: \(d.membersCount)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if d.isOwner {
                Button { newTitle = d.title ?? ""; showRename = true } label: {
                    Label("Переименовать", systemImage: "pencil")
                }
            }
        }
        Section("Участники") {
            ForEach(d.members) { member in
                NavigationLink { PublicProfileView(userID: member.id) } label: {
                    HStack(spacing: 12) {
                        AvatarCircle(url: member.avatarURL, name: member.name, size: 40)
                        Text(member.name ?? "Без имени")
                        Spacer()
                        if member.id == auth.me?.id {
                            Text("вы").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if d.isOwner, member.id != auth.me?.id {
                        Button(role: .destructive) { Task { await remove(member.id) } } label: {
                            Label("Убрать", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
            if d.isOwner {
                Button { showAddMembers = true } label: {
                    Label("Добавить участников", systemImage: "person.badge.plus")
                }
            }
        }
        Section {
            Button(role: .destructive) { showLeaveConfirm = true } label: {
                Label("Выйти из группы", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        if let errorText { Text(errorText).foregroundStyle(.red) }
    }

    private func load() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            detail = try await auth.api.send(Endpoint(path: "/conversations/\(conversationID)"))
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось загрузить группу. Проверьте соединение."
        }
    }

    private func rename() async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            detail = try await auth.api.send(Endpoint(
                path: "/conversations/\(conversationID)", method: .patch,
                body: UpdateConversationBody(title: trimmed)))
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось переименовать" }
    }

    private func remove(_ userID: String) async {
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/conversations/\(conversationID)/members/\(userID)", method: .delete))
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось убрать участника" }
    }

    private func leave() async {
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/conversations/\(conversationID)/leave", method: .post))
            left = true
            dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось выйти из группы" }
    }
}

/// Выбор новых участников — те же кандидаты-со-участники, минус уже состоящие.
private struct AddMembersSheet: View {
    let conversationID: String
    let existingIDs: Set<String>
    var onDone: () -> Void

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [UserPublic] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                } else if candidates.isEmpty {
                    Text("Некого добавить: все знакомые уже в группе.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(candidates) { user in
                    Button {
                        if selected.contains(user.id) { selected.remove(user.id) }
                        else { selected.insert(user.id) }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarCircle(url: user.avatarURL, name: user.name, size: 40)
                            Text(user.name ?? "Без имени").foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: selected.contains(user.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(user.id) ? Theme.accent : Theme.line)
                        }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Добавить участников")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить") { Task { await add() } }.disabled(selected.isEmpty)
                }
            }
            .task { await loadCandidates() }
        }
    }

    private func loadCandidates() async {
        isLoading = true
        defer { isLoading = false }
        guard let list: ConversationListResponse =
                try? await auth.api.send(Endpoint(path: "/conversations")) else { return }
        var seen: [String: UserPublic] = [:]
        for conv in list.items.prefix(20) {
            if let detail: ConversationDetail =
                try? await auth.api.send(Endpoint(path: "/conversations/\(conv.id)")) {
                for member in detail.members
                where member.id != auth.me?.id && !existingIDs.contains(member.id) {
                    seen[member.id] = member
                }
            }
        }
        candidates = seen.values.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func add() async {
        do {
            let _: ConversationDetail = try await auth.api.send(Endpoint(
                path: "/conversations/\(conversationID)/members", method: .post,
                body: AddMembersBody(user_ids: Array(selected))))
            onDone()
            dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось добавить участников" }
    }
}
