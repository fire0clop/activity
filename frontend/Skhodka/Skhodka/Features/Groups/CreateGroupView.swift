import SwiftUI

/// Создание самостоятельной группы (V2): имя + участники из прошлых со-участников.
struct CreateGroupView: View {
    /// Если группа создаётся «из события» — бэк добавит его accepted-участников сам.
    var fromEventID: String? = nil
    var onCreated: ((ConversationDetail) -> Void)? = nil

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var candidates: [UserPublic] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var errorText: String?

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (fromEventID != nil || !selected.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, «Субботний теннис»", text: $title)
                }
                Section(fromEventID != nil ? "Позвать ещё (участники события добавятся сами)" : "Участники") {
                    if isLoading {
                        ProgressView()
                    } else if candidates.isEmpty {
                        Text("Пока не с кем: со-участники появятся после первых событий.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { user in
                            Button { toggle(user.id) } label: {
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
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isCreating ? "…" : "Создать") { Task { await create() } }
                        .disabled(!canCreate || isCreating)
                }
            }
            .task { await loadCandidates() }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Кандидаты — участники всех моих бесед (со-участники прошлых событий и групп).
    private func loadCandidates() async {
        isLoading = true
        defer { isLoading = false }
        let list: ConversationListResponse
        do {
            list = try await auth.api.send(Endpoint(path: "/conversations"))
            errorText = nil
        } catch let err as APIError { errorText = err.message; return }
        catch { errorText = "Не удалось загрузить список. Проверьте соединение."; return }

        var seen: [String: UserPublic] = [:]
        for conv in list.items.prefix(20) {
            if let detail: ConversationDetail =
                try? await auth.api.send(Endpoint(path: "/conversations/\(conv.id)")) {
                for member in detail.members where member.id != auth.me?.id {
                    seen[member.id] = member
                }
            }
        }
        candidates = seen.values.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func create() async {
        isCreating = true; errorText = nil
        defer { isCreating = false }
        do {
            let detail: ConversationDetail = try await auth.api.send(Endpoint(
                path: "/conversations", method: .post,
                body: CreateGroupBody(
                    title: title.trimmingCharacters(in: .whitespaces),
                    member_ids: Array(selected),
                    from_event_id: fromEventID)))
            onCreated?(detail)
            dismiss()
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось создать группу. Проверьте соединение."
        }
    }
}
