import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var showEdit = false
    @State private var showPasswordReset = false
    @State private var fullScreen = false
    @State private var startIndex = 0

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
            actionRow("Телефон", value: auth.me?.phone ?? "", icon: "phone.fill") {}
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Сменить пароль", value: nil, icon: "lock.fill") { showPasswordReset = true }
            Divider().background(Theme.line).padding(.leading, 50)
            actionRow("Выйти", value: nil, icon: "rectangle.portrait.and.arrow.right", destructive: true) { auth.signOut() }
        }
        .cardStyle()
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
