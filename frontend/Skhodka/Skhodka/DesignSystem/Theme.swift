import SwiftUI
import UIKit

/// Дизайн-система «Сходка» — editorial / журнальный стиль:
/// бумажный фон, серифные заголовки, один тёплый акцент, цветные категории.
enum Theme {
    // Палитра «бумага»
    static let paper = Color(red: 0.98, green: 0.966, blue: 0.93)      // тёплый офф-вайт фон
    static let surface = Color.white                                    // карточки
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.08)          // тёмный текст
    static let ink2 = Color(red: 0.34, green: 0.32, blue: 0.28)         // вторичный текст (≥4.5:1 на бумаге)
    static let line = Color(red: 0.90, green: 0.88, blue: 0.82)         // хайрлайны
    static let accent = Color(red: 1.0, green: 0.31, blue: 0.18)        // коралл-акцент (крупные кнопки/иконки)
    static let accentInk = Color(red: 0.85, green: 0.24, blue: 0.10)    // затемнённый коралл для ТЕКСТА/ссылок/пузырей (≥4.5:1)
    static let accentSoft = Color(red: 1.0, green: 0.31, blue: 0.18).opacity(0.12)
    static let star = Color(red: 0.98, green: 0.70, blue: 0.10)         // цвет рейтинга-звезды
    static let danger = Color(red: 0.85, green: 0.20, blue: 0.16)       // ошибки/деструктив

    // Совместимость со старым кодом
    static let bg = paper
    static let secondaryBg = Color(red: 0.95, green: 0.935, blue: 0.89) // поля ввода
    static let cornerRadius: CGFloat = 20
}

enum Radii {
    static let card: CGFloat = 22
    static let pill: CGFloat = 100
    static let sm: CGFloat = 14
}

/// Шкала отступов — вместо разрозненных 8/10/12/14/16 по экранам.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Тактильный отклик. Приложение-чат без хаптики ощущается «мёртвым».
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Нажатие карточки: лёгкое «поддавливание» вместо мёртвого `.buttonStyle(.plain)`.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Категории (иконка + цвет + короткое имя)

struct CategoryStyle {
    let title: String
    let icon: String
    let color: Color
}

enum Categories {
    static let map: [String: CategoryStyle] = [
        "watersport": .init(title: "Вода", icon: "drop.fill", color: Color(red: 0.16, green: 0.54, blue: 1.0)),
        "tennis": .init(title: "Спорт", icon: "figure.tennis", color: Color(red: 0.15, green: 0.70, blue: 0.42)),
        "sport": .init(title: "Спорт", icon: "figure.run", color: Color(red: 0.15, green: 0.70, blue: 0.42)),
        "music": .init(title: "Музыка", icon: "music.note", color: Color(red: 0.49, green: 0.36, blue: 1.0)),
        "concert": .init(title: "Концерт", icon: "music.mic", color: Color(red: 0.49, green: 0.36, blue: 1.0)),
        "boardgames": .init(title: "Настолки", icon: "die.face.5.fill", color: Color(red: 0.95, green: 0.63, blue: 0.07)),
        "walk": .init(title: "Прогулка", icon: "figure.walk", color: Color(red: 0.06, green: 0.71, blue: 0.64)),
        "food": .init(title: "Еда", icon: "fork.knife", color: Color(red: 0.92, green: 0.43, blue: 0.30)),
    ]

    static func of(_ key: String?) -> CategoryStyle {
        if let key, let c = map[key.lowercased()] { return c }
        return .init(title: key?.isEmpty == false ? key! : "Событие", icon: "sparkles", color: Theme.accent)
    }

    /// Упорядоченный набор ключей для выбора чипами (без дублей по смыслу).
    static let pickable = ["walk", "sport", "watersport", "music", "boardgames", "food"]
}

// MARK: - Типографика (сериф для заголовков = журнальный вид)

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func serifTitle(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Компоненты

/// Бейдж категории: иконка + название на цветной плашке.
struct CategoryBadge: View {
    let category: String?
    var compact: Bool = false
    var body: some View {
        let c = Categories.of(category)
        HStack(spacing: 5) {
            Image(systemName: c.icon).font(.system(size: compact ? 10 : 12, weight: .bold))
            if !compact { Text(c.title.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.5) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 5 : 6)
        .background(c.color)
        .clipShape(Capsule())
    }
}

/// Цветная «обложка-заглушка» по категории, если у события нет фото.
struct CategoryCover: View {
    let category: String?
    var body: some View {
        let c = Categories.of(category)
        ZStack {
            LinearGradient(colors: [c.color, c.color.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: c.icon)
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Главная кнопка действия.
struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(title).font(.system(size: 17, weight: .bold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Theme.accent : Theme.ink.opacity(0.18))
            .foregroundStyle(isEnabled ? .white : Theme.ink2)
            .clipShape(RoundedRectangle(cornerRadius: Radii.sm))
        }
        .disabled(!isEnabled || isLoading)
    }
}

struct RatingView: View {
    let value: Double
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").foregroundStyle(Theme.star).font(.caption2)
            Text(count > 0 ? String(format: "%.1f", value) : "—")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
            if count > 0 { Text("(\(count))").font(.caption2).foregroundStyle(Theme.ink2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0
            ? "Рейтинг \(String(format: "%.1f", value)) из 5, отзывов: \(count)"
            : "Рейтинга пока нет")
    }
}

/// Стопка аватаров «уже идут».
struct AvatarStack: View {
    let urls: [String?]
    let names: [String?]
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(Array(urls.prefix(5).enumerated()), id: \.offset) { i, url in
                AvatarCircle(url: url, name: names[safe: i] ?? nil, size: size)
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
        }
    }
}

struct AvatarCircle: View {
    let url: String?
    let name: String?
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { initials }
            } else { initials }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    private var initials: some View {
        Theme.accentSoft.overlay(
            Text(String(name?.prefix(1).uppercased() ?? "•"))
                .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.accent))
    }
}

struct StarPicker: View {
    @Binding var rating: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.title3).foregroundStyle(i <= rating ? Theme.star : Theme.line)
                    .onTapGesture { rating = i; Haptics.tap() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оценка")
        .accessibilityValue("\(rating) из 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(1, rating - 1)
            @unknown default: break
            }
        }
    }
}

extension View {
    /// Бумажный фон экрана.
    func paperBackground() -> some View { background(Theme.paper.ignoresSafeArea()) }
    func cardStyle() -> some View {
        background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Radii.card))
            .overlay(RoundedRectangle(cornerRadius: Radii.card).stroke(Theme.line, lineWidth: 1))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
