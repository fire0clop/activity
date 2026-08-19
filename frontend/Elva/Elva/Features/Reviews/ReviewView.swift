import SwiftUI

/// Двусторонние отзывы после завершённого события: оцениваешь остальных участников и организатора.
struct ReviewView: View {
    let event: EventDetail
    @EnvironmentObject var auth: AuthManager
    @State private var ratings: [String: Int] = [:]
    @State private var comments: [String: String] = [:]
    @State private var done: Set<String> = []
    /// Кого отмечают как не пришедшего: оценки у такого отзыва нет.
    @State private var noShows: Set<String> = []
    @State private var busyIDs: Set<String> = []
    /// Ошибка привязана к строке, а не к экрану.
    @State private var rowErrors: [String: String] = [:]

    private var targets: [OrganizerBrief] {
        event.acceptedParticipants.filter { $0.id != auth.me?.id }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                if targets.isEmpty {
                    EmptyState(icon: "star.bubble", title: "Некого оценивать",
                               subtitle: "Отзывы появляются, когда на встрече был кто-то ещё.")
                }
                ForEach(targets) { p in card(p) }
            }
            .padding(16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Отзывы")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ p: OrganizerBrief) -> some View {
        let absent = noShows.contains(p.id)
        let isDone = done.contains(p.id)
        let busy = busyIDs.contains(p.id)
        let canSend = absent || (ratings[p.id] ?? 0) > 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarCircle(url: p.avatarURL, name: p.name, size: 40)
                Text(p.name ?? "Участник")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if isDone {
                    Label("Готово", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentInk)
                }
            }
            if !isDone {
                if absent {
                    Text("Отмечаем, что человек не пришёл. Оценка не ставится — это не «единица», а отдельный факт в профиле.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                } else {
                    StarPicker(rating: binding(for: p.id))
                }
                TextField(absent ? "Что случилось (необязательно)" : "Комментарий (необязательно)",
                          text: commentBinding(for: p.id), axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Theme.secondaryBg,
                                in: RoundedRectangle(cornerRadius: Radii.sm, style: .continuous))
                // Ошибка живёт рядом со строкой, которая её вызвала: на списке из
                // десяти человек общая ошибка внизу экрана бесполезна.
                if let e = rowErrors[p.id] {
                    Text(e).font(.caption).foregroundStyle(Theme.dangerInk)
                }
                HStack(spacing: 10) {
                    Button { Task { await submit(p) } } label: {
                        actionLabel(absent ? "Отметить неявку" : "Отправить отзыв",
                                    filled: true, loading: busy)
                    }
                    .disabled(busy || !canSend)
                    .opacity(canSend ? 1 : 0.5)

                    Button {
                        withAnimation {
                            if absent { noShows.remove(p.id) } else { noShows.insert(p.id) }
                        }
                    } label: {
                        actionLabel(absent ? "Всё-таки пришёл" : "Не пришёл", filled: false)
                    }
                    .disabled(busy)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Тот же вид кнопки, что в составе события: отбор людей и оценка людей —
    /// один сценарий, и кнопки в нём обязаны выглядеть одинаково.
    private func actionLabel(_ title: String, filled: Bool, loading: Bool = false) -> some View {
        ZStack {
            if loading { ProgressView().controlSize(.small).tint(filled ? .white : Theme.ink) }
            else { Text(title).font(.system(size: 15, weight: .semibold)) }
        }
        .foregroundStyle(filled ? .white : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(filled ? Theme.accent : Theme.secondaryBg,
                    in: RoundedRectangle(cornerRadius: Radii.sm, style: .continuous))
    }

    private func binding(for id: String) -> Binding<Int> {
        Binding(get: { ratings[id] ?? 0 }, set: { ratings[id] = $0 })
    }
    private func commentBinding(for id: String) -> Binding<String> {
        Binding(get: { comments[id] ?? "" }, set: { comments[id] = $0 })
    }

    private func submit(_ p: OrganizerBrief) async {
        rowErrors[p.id] = nil
        busyIDs.insert(p.id)
        defer { busyIDs.remove(p.id) }
        let comment = comments[p.id]?.trimmingCharacters(in: .whitespaces)
        let attended = !noShows.contains(p.id)
        let body = ReviewCreateBody(
            target_id: p.id,
            rating: attended ? (ratings[p.id] ?? 0) : nil,
            comment: (comment?.isEmpty == false) ? comment : nil,
            attended: attended)
        do {
            let _: Review = try await auth.api.send(Endpoint(
                path: "/events/\(event.id)/reviews", method: .post, body: body))
            done.insert(p.id)
        } catch let err as APIError {
            if err.isCode(.alreadyReviewed) { done.insert(p.id) } else { rowErrors[p.id] = err.message }
        } catch { rowErrors[p.id] = "Не удалось отправить отзыв" }
    }

}
