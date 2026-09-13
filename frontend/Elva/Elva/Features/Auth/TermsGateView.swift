import SwiftUI

/// Правила сообщества перед входом.
///
/// App Store 1.2 требует, чтобы приложение с пользовательским контентом
/// показывало условия использования до регистрации или входа, и чтобы в них
/// была нулевая терпимость к оскорбительному контенту. Экран стоит перед всем
/// потоком авторизации: не согласился — дальше не попадёшь.
enum Terms {
    static let version = "1.0"
    static let storageKey = "tos.accepted.version"
    static let fullTextURL = URL(string: "https://event-serv.ru/rules")!
}

struct TermsGateView: View {
    var onAccept: () -> Void

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Правила сообщества")
                            .font(.serifTitle(30, weight: .bold)).foregroundStyle(Theme.ink)
                            .padding(.top, 28)
                        Text("Elva — про то, чтобы встречаться вживую. Эти правила существуют, чтобы на встречу можно было прийти спокойно.")
                            .font(.system(size: 15)).foregroundStyle(Theme.ink2)

                        rule("nosign", "Нулевая терпимость",
                             "Оскорбления, травля, угрозы, ненависть по любому признаку, сексуальный контент и обман запрещены. Аккаунт нарушителя удаляется без предупреждения.")
                        rule("flag.fill", "Жалобы разбираются за 24 часа",
                             "На любом событии и в любом профиле есть «Пожаловаться». Недопустимый контент удаляется, его автор блокируется.")
                        rule("hand.raised.fill", "Блокировка работает сразу",
                             "Заблокированный человек мгновенно исчезает из вашей ленты и не может откликаться на ваши события. О блокировке узнаёт модерация.")
                        rule("person.fill.checkmark", "Вы отвечаете за свой контент",
                             "Публикуя события, фотографии, сообщения и отзывы, вы соглашаетесь, что они соответствуют этим правилам.")

                        Link(destination: Terms.fullTextURL) {
                            Text("Полный текст правил")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        onAccept()
                    } label: {
                        Text("Принимаю правила")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .accessibilityIdentifier("terms.accept")
                    Text("Без согласия пользоваться приложением нельзя.")
                        .font(.footnote).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func rule(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.system(size: 14)).foregroundStyle(Theme.ink2).lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Чекбокс согласия с правилами на экранах входа и регистрации (App Store 1.2):
/// продолжить нельзя, пока согласие не дано; ссылка ведёт на полный текст.
/// Согласие едино с TermsGateView — принятые на гейте правила отмечают чекбокс,
/// поэтому существующих пользователей он не тормозит.
struct TermsConsentRow: View {
    @Binding var agreed: Bool
    @AppStorage(Terms.storageKey) private var tosAccepted = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Haptics.tap()
                agreed.toggle()
                // Пишем только согласие: снятие галочки блокирует кнопки локально,
                // но не сбрасывает принятие на гейте (иначе RootView вернул бы гейт).
                if agreed { tosAccepted = Terms.version }
            } label: {
                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(agreed ? Theme.accent : Theme.ink2)
            }
            .accessibilityLabel("Согласие с правилами сообщества")
            .accessibilityValue(agreed ? "принято" : "не принято")

            (Text("Принимаю ")
                + Text("правила сообщества").underline().foregroundColor(Theme.accentInk)
                + Text(" — нулевая терпимость к оскорбительному контенту"))
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
                .onTapGesture { UIApplication.shared.open(Terms.fullTextURL) }

            Spacer(minLength: 0)
        }
        .onAppear {
            if tosAccepted == Terms.version { agreed = true }
        }
    }
}
