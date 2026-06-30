import SwiftUI

/// Двусторонние отзывы после завершённого события: оцениваешь остальных участников и организатора.
struct ReviewView: View {
    let event: EventDetail
    @EnvironmentObject var auth: AuthManager
    @State private var ratings: [String: Int] = [:]
    @State private var comments: [String: String] = [:]
    @State private var done: Set<String> = []
    @State private var errorText: String?

    private var targets: [OrganizerBrief] {
        event.acceptedParticipants.filter { $0.id != auth.me?.id }
    }

    var body: some View {
        List {
            if targets.isEmpty {
                Text("Некого оценивать").foregroundStyle(.secondary)
            }
            ForEach(targets) { p in
                Section {
                    HStack(spacing: 10) {
                        avatar(p.avatarURL, name: p.name)
                        Text(p.name ?? "Участник").fontWeight(.medium)
                        Spacer()
                        if done.contains(p.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if !done.contains(p.id) {
                        StarPicker(rating: binding(for: p.id))
                        TextField("Комментарий (необязательно)", text: commentBinding(for: p.id), axis: .vertical)
                            .lineLimit(1...3)
                        Button("Отправить отзыв") { Task { await submit(p) } }
                            .disabled((ratings[p.id] ?? 0) == 0)
                    }
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle("Отзывы")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for id: String) -> Binding<Int> {
        Binding(get: { ratings[id] ?? 0 }, set: { ratings[id] = $0 })
    }
    private func commentBinding(for id: String) -> Binding<String> {
        Binding(get: { comments[id] ?? "" }, set: { comments[id] = $0 })
    }

    private func submit(_ p: OrganizerBrief) async {
        errorText = nil
        let comment = comments[p.id]?.trimmingCharacters(in: .whitespaces)
        let body = ReviewCreateBody(
            target_id: p.id, rating: ratings[p.id] ?? 0,
            comment: (comment?.isEmpty == false) ? comment : nil)
        do {
            let _: Review = try await auth.api.send(Endpoint(
                path: "/events/\(event.id)/reviews", method: .post, body: body))
            done.insert(p.id)
        } catch let err as APIError {
            if err.code == "already_reviewed" { done.insert(p.id) } else { errorText = err.message }
        } catch { errorText = "Не удалось отправить отзыв" }
    }

    private func avatar(_ url: String?, name: String?) -> some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
            } else {
                Theme.secondaryBg.overlay(Text(String(name?.prefix(1) ?? "?")))
            }
        }.frame(width: 40, height: 40).clipShape(Circle())
    }
}
