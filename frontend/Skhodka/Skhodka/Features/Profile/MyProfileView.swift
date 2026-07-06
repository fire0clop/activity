import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var showEdit = false
    @State private var showPasswordReset = false
    @State private var fullScreen = false
    @State private var startIndex = 0
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.paper.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let me = auth.me {
                            heroCard(me)
                            if !me.photoURLs.isEmpty { photos(me) }
                            statsCard(me)
                            actionsCard
                            legalCard
                            if let deleteError {
                                Text(deleteError).font(.footnote).foregroundStyle(.red)
                            }
                        }
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 18).padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showEdit) { if let me = auth.me { EditProfileView(me: me) } }
            .fullScreenCover(isPresented: $fullScreen) {
                FullScreenPhotoView(images: auth.me?.photoURLs ?? [], start: startIndex)
            }
            .sheet(isPresented: $showPasswordReset) {
                NavigationStack { PasswordResetView(prefillPhone: auth.me?.phone ?? "", asSheet: true) }
            }
            .confirmationDialog("Удалить аккаунт?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить навсегда", role: .destructive) { Task { await deleteAccount() } }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Профиль, ваши события и заявки будут удалены безвозвратно. Это действие нельзя отменить.")
            }
            .task { await auth.refreshMe() }
        }
    }

    private var header: some View {
        HStack {
            Text("Профиль").font(.display(34)).foregroundStyle(Theme.ink)
            Spacer()
            Button { showEdit = true } label: {
                Text("Изменить").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.surface).clipShape(Capsule()).overlay(Capsule().stroke(Theme.line))
            }
        }
    }

    private func heroCard(_ me: UserPrivate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AvatarCircle(url: me.avatarURL, name: me.name, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(me.name ?? "Без имени").font(.serifTitle(24, weight: .bold)).foregroundStyle(Theme.ink)
                    RatingView(value: me.ratingAvg, count: me.ratingCount)
                    Text("в приложении с \(DateFormat.prettyDateTime(me.memberSince))")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
            }
            if let bio = me.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 15)).foregroundStyle(Theme.ink.opacity(0.85))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }

    private func photos(_ me: UserPrivate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ФОТО").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(Theme.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(me.photoURLs.enumerated()), id: \.offset) { i, p in
                        if let u = URL(string: p) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
                                .frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 14))
                                .onTapGesture { startIndex = i; fullScreen = true }
                        }
                    }
                }
            }
        }
    }

    private func statsCard(_ me: UserPrivate) -> some View {
        HStack(spacing: 0) {
            stat("\(me.eventsCreated)", "Создано")
            divider
            stat("\(me.eventsAttended)", "Посещено")
            divider
            stat("\(me.ratingCount)", "Отзывов")
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity).cardStyle()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.serifTitle(22, weight: .bold)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.ink2)
        }.frame(maxWidth: .infinity)
    }
    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 32) }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            NavigationLink { MyEventsView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent).frame(width: 26)
                    Text("Мои события").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Телефон", value: auth.me?.phone ?? "", icon: "phone.fill") {}
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Сменить пароль", value: nil, icon: "lock.fill") { showPasswordReset = true }
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Выйти", value: nil, icon: "rectangle.portrait.and.arrow.right", destructive: true) { auth.signOut() }
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Удалить аккаунт", value: nil, icon: "trash.fill", destructive: true) { confirmDelete = true }
        }
        .cardStyle()
    }

    private var legalCard: some View {
        VStack(spacing: 0) {
            Link(destination: Legal.privacyPolicyURL) {
                legalRow("Политика конфиденциальности", icon: "hand.raised.fill")
            }
            Divider().background(Theme.line).padding(.leading, 50)
            Link(destination: Legal.termsURL) {
                legalRow("Правила сообщества", icon: "doc.text.fill")
            }
        }
        .cardStyle()
    }

    private func legalRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent).frame(width: 26)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    private func deleteAccount() async {
        deleteError = nil
        do {
            try await auth.api.sendVoid(Endpoint(path: "/users/me", method: .delete))
            auth.accountDeleted()
        } catch let err as APIError {
            deleteError = err.message
        } catch {
            deleteError = "Не удалось удалить аккаунт. Попробуйте позже."
        }
    }

    private func actionRow(_ title: String, value: String?, icon: String, destructive: Bool = false,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(destructive ? .red : Theme.accent).frame(width: 26)
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(destructive ? .red : Theme.ink)
                Spacer()
                if let value { Text(value).font(.system(size: 15)).foregroundStyle(Theme.ink2) }
                else if !destructive { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2) }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
        }.buttonStyle(.plain)
    }
}
