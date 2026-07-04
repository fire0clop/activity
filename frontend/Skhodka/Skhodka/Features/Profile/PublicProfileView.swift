import SwiftUI

struct PublicProfileView: View {
    let userID: String
    @EnvironmentObject var auth: AuthManager
    @State private var user: UserPublic?
    @State private var isLoading = true
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var isBlocked = false
    @State private var statusText: String?
    @State private var actionError: String?
    @State private var fullScreen = false
    @State private var startIndex = 0
    @State private var reviews: [Review] = []

    var body: some View {
        ScrollView {
            if let u = user {
                content(u)
            } else if isLoading {
                ProgressView().padding(40)
            } else {
                Text("Профиль не найден").foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $fullScreen) {
            FullScreenPhotoView(images: user?.photoURLs ?? [], start: startIndex)
        }
        .task { await load() }
        .confirmationDialog("Пожаловаться на пользователя", isPresented: $showReport, titleVisibility: .visible) {
            Button("Спам") { Task { await report("spam") } }
            Button("Неуместное поведение") { Task { await report("inappropriate") } }
            Button("Безопасность") { Task { await report("safety") } }
            Button("Другое") { Task { await report("other") } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Заблокировать пользователя?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Заблокировать", role: .destructive) { Task { await setBlocked(true) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы перестанете видеть события этого пользователя, а он не сможет откликаться на ваши.")
        }
    }

    @ViewBuilder
    private func content(_ u: UserPublic) -> some View {
        VStack(spacing: 16) {
            avatar(u.avatarURL, name: u.name).frame(width: 96, height: 96)
            Text(u.name ?? "Пользователь").font(.title2).fontWeight(.bold)
            RatingView(value: u.ratingAvg, count: u.ratingCount)
            if let bio = u.bio, !bio.isEmpty {
                Text(bio).multilineTextAlignment(.center).padding(.horizontal)
            }
            HStack(spacing: 20) {
                stat("Создал", u.eventsCreated)
                stat("Посетил", u.eventsAttended)
            }

            if !u.photoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(u.photoURLs.enumerated()), id: \.offset) { i, p in
                            if let url = URL(string: p) {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture { startIndex = i; fullScreen = true }
                            }
                        }
                    }.padding(.horizontal)
                }
            }

            if !reviews.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Отзывы").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(reviews) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.author.name ?? "Аноним").font(.subheadline).fontWeight(.medium)
                                Spacer()
                                RatingView(value: Double(r.rating), count: 0)
                            }
                            if let c = r.comment, !c.isEmpty {
                                Text(c).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                }.padding(.top, 4)
            }

            if let statusText {
                Text(statusText).font(.footnote).foregroundStyle(.secondary)
            }
            if let actionError {
                Text(actionError).font(.footnote).foregroundStyle(.red)
            }

            if u.id != auth.me?.id {
                VStack(spacing: 10) {
                    Button(role: .destructive) { showReport = true } label: {
                        Label("Пожаловаться", systemImage: "exclamationmark.bubble")
                    }
                    if isBlocked {
                        Button { Task { await setBlocked(false) } } label: {
                            Label("Разблокировать", systemImage: "hand.raised.slash")
                        }
                    } else {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("Заблокировать", systemImage: "hand.raised")
                        }
                    }
                }.padding(.top, 8)
            }
        }
        .padding()
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack { Text("\(value)").font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) }
    }

    private func avatar(_ url: String?, name: String?) -> some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
            } else {
                Theme.secondaryBg.overlay(Text(String(name?.prefix(1) ?? "?")).font(.title))
            }
        }.clipShape(Circle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        user = try? await auth.api.send(Endpoint(path: "/users/\(userID)"))
        if let resp: ReviewsResponse = try? await auth.api.send(Endpoint(path: "/users/\(userID)/reviews")) {
            reviews = resp.items
        }
    }

    private func report(_ reason: String) async {
        statusText = nil; actionError = nil
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/reports", method: .post,
                body: ReportBody(target_user_id: userID, target_event_id: nil, reason: reason, comment: nil)))
            statusText = "Жалоба отправлена. Спасибо."
        } catch let err as APIError {
            actionError = err.message
        } catch {
            actionError = "Не удалось отправить жалобу. Проверьте соединение."
        }
    }

    private func setBlocked(_ blocked: Bool) async {
        statusText = nil; actionError = nil
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/users/\(userID)/block", method: blocked ? .post : .delete))
            isBlocked = blocked
            statusText = blocked ? "Пользователь заблокирован." : "Пользователь разблокирован."
        } catch let err as APIError {
            actionError = err.message
        } catch {
            actionError = "Не удалось выполнить действие. Проверьте соединение."
        }
    }
}
