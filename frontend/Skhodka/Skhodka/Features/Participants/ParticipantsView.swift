import SwiftUI

struct ParticipantsView: View {
    let eventID: String
    @EnvironmentObject var auth: AuthManager
    @State private var pending: [ParticipantItem] = []
    @State private var accepted: [ParticipantItem] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            if !pending.isEmpty {
                Section("Заявки") {
                    ForEach(pending) { p in
                        row(p, showActions: true)
                    }
                }
            }
            Section("Участники") {
                if accepted.isEmpty {
                    Text("Пока никого").foregroundStyle(.secondary)
                }
                ForEach(accepted) { p in row(p, showActions: false) }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Участники")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ p: ParticipantItem, showActions: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.secondaryBg).frame(width: 40, height: 40)
                .overlay(Text(String(p.user.name?.prefix(1) ?? "?")))
            VStack(alignment: .leading) {
                Text(p.user.name ?? "Пользователь").fontWeight(.medium)
                RatingView(value: p.user.ratingAvg, count: p.user.ratingCount)
            }
            Spacer()
            if showActions {
                Button { Task { await decide(p, accept: true) } } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }.buttonStyle(.plain)
                Button { Task { await decide(p, accept: false) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let p: ParticipantsResponse = auth.api.send(Endpoint(
                path: "/events/\(eventID)/participants", query: ["status": "pending"]))
            async let a: ParticipantsResponse = auth.api.send(Endpoint(
                path: "/events/\(eventID)/participants", query: ["status": "accepted"]))
            let (pr, ar) = try await (p, a)
            pending = pr.items; accepted = ar.items
            errorText = nil
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось загрузить участников. Проверьте соединение." }
    }

    private func decide(_ p: ParticipantItem, accept: Bool) async {
        errorText = nil
        let path = "/participations/\(p.participationID)/\(accept ? "accept" : "reject")"
        do {
            let _: JoinResponse = try await auth.api.send(Endpoint(path: path, method: .post))
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось обработать заявку. Попробуйте ещё раз." }
    }
}
