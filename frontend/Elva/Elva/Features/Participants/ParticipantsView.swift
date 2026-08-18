import SwiftUI

/// Состав события глазами организатора.
///
/// Заявка — это решение о том, кого позвать на реальную встречу, поэтому строка списка
/// показывает человека, а не только имя: фото, возраст, «о себе», рейтинг или пометку
/// «Новичок», сколько встреч за плечами и были ли неявки. Полный профиль — по тапу.
struct ParticipantsView: View {
    let eventID: String
    var isOrganizer: Bool = true

    @EnvironmentObject var auth: AuthManager
    @State private var pending: [ParticipantItem] = []
    @State private var accepted: [ParticipantItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorText: String?
    @State private var busyIDs: Set<String> = []
    @State private var toRemove: ParticipantItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 4)
                }

                if isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
                } else if loadFailed {
                    ErrorState { Task { await load() } }
                } else {
                    if isOrganizer && !pending.isEmpty {
                        section("Ждут ответа", count: pending.count) {
                            ForEach(pending) { card($0, kind: .request) }
                        }
                    }
                    section("Идут", count: accepted.count) {
                        if accepted.isEmpty {
                            Text("Пока никого. Первый согласившийся появится здесь.")
                                .font(.subheadline).foregroundStyle(Theme.ink2)
                                .padding(.vertical, 6)
                        }
                        ForEach(accepted) { card($0, kind: isOrganizer ? .member : .plain) }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Состав")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Освободить место \(toRemove?.user.name ?? "участника")?",
            isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Убрать из состава", role: .destructive) {
                if let p = toRemove { Task { await remove(p) } }
            }
            Button("Отмена", role: .cancel) { toRemove = nil }
        } message: {
            Text("Человек выйдет из чата и получит уведомление. Место уйдёт первому из очереди.")
        }
    }

    // MARK: - Секция

    @ViewBuilder
    private func section<C: View>(_ title: String, count: Int,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title).font(.serifTitle(21, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(count)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.secondaryBg, in: Capsule())
            }
            .padding(.leading, 4)
            content()
        }
    }

    // MARK: - Карточка человека

    private enum RowKind { case request, member, plain }

    private func card(_ p: ParticipantItem, kind: RowKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { PublicProfileView(userID: p.user.id) } label: {
                HStack(alignment: .top, spacing: 12) {
                    AvatarCircle(url: p.user.avatarURL, name: p.user.name, size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(p.user.name ?? "Участник")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            if let age = p.user.age {
                                Text("\(age)").font(.system(size: 14)).foregroundStyle(Theme.ink2)
                            }
                        }
                        // Репутация: рейтинг либо честная пометка «Новичок», плюс неявки.
                        HStack(spacing: 6) {
                            RatingView(value: p.user.ratingAvg, count: p.user.ratingCount,
                                       showsNewcomer: true)
                            NoShowBadge(count: p.user.noShows)
                        }
                        Text(experience(p.user))
                            .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
                        .padding(.top, 6)
                }
            }
            .buttonStyle(.plain)

            // «О себе» — то, по чему организатор реально принимает решение.
            if let bio = p.user.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.secondaryBg, in: RoundedRectangle(cornerRadius: Radii.sm))
            } else if kind == .request {
                Text("Профиль без рассказа о себе — можно спросить в чате после приёма.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ink2)
            }

            switch kind {
            case .request:
                HStack(spacing: 10) {
                    Button { Task { await decide(p, accept: true) } } label: {
                        actionLabel("Принять", filled: true)
                    }
                    Button { Task { await decide(p, accept: false) } } label: {
                        actionLabel("Отказать", filled: false)
                    }
                }
                .disabled(busyIDs.contains(p.id))
                .opacity(busyIDs.contains(p.id) ? 0.5 : 1)
            case .member:
                Button { toRemove = p } label: {
                    Text("Освободить место")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
                }
                .disabled(busyIDs.contains(p.id))
            case .plain:
                EmptyView()
            }
        }
        .padding(14)
        .cardStyle()
    }

    private func actionLabel(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? .white : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(filled ? Theme.accent : Theme.secondaryBg,
                        in: RoundedRectangle(cornerRadius: Radii.sm))
    }

    /// Короткая строка опыта: чем человек уже занимался в приложении.
    private func experience(_ u: UserPublic) -> String {
        var parts: [String] = []
        if u.eventsAttended > 0 { parts.append("встреч: \(u.eventsAttended)") }
        if u.eventsCreated > 0 { parts.append("своих событий: \(u.eventsCreated)") }
        return parts.isEmpty ? "Ещё не был ни на одной встрече" : parts.joined(separator: " · ")
    }

    // MARK: - Данные

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
            errorText = nil; loadFailed = false
        } catch let err as APIError {
            errorText = err.message; loadFailed = accepted.isEmpty && pending.isEmpty
        } catch {
            errorText = nil; loadFailed = true
        }
    }

    private func decide(_ p: ParticipantItem, accept: Bool) async {
        errorText = nil
        busyIDs.insert(p.id)
        defer { busyIDs.remove(p.id) }
        let path = "/participations/\(p.participationID)/\(accept ? "accept" : "reject")"
        do {
            let _: JoinResponse = try await auth.api.send(Endpoint(path: path, method: .post))
            Haptics.success()
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось обработать заявку. Попробуйте ещё раз." }
    }

    private func remove(_ p: ParticipantItem) async {
        errorText = nil
        toRemove = nil
        busyIDs.insert(p.id)
        defer { busyIDs.remove(p.id) }
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/participations/\(p.participationID)", method: .delete))
            Haptics.warning()
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось освободить место. Попробуйте ещё раз." }
    }
}
