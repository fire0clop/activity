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
    static let line = Color(red: 0.90, green: 0.88, blue: 0.82)         // декоративные разделители
    static let lineStrong = Color(red: 0.80, green: 0.77, blue: 0.70)   // обводка карточек и полей
    static let inkMuted = Color(red: 0.58, green: 0.55, blue: 0.48)     // выключенные глифы, пустые звёзды
    static let skeleton = Color(red: 0.91, green: 0.895, blue: 0.855)   // заглушки загрузки
    static let accent = Color(red: 1.0, green: 0.31, blue: 0.18)        // коралл: заливки и иконки
    // Текст и заливки под белым текстом: 5.2:1 на бумаге, 5.6:1 под белым.
    static let accentInk = Color(red: 0.76, green: 0.19, blue: 0.06)
    static let accentSoft = Color(red: 1.0, green: 0.31, blue: 0.18).opacity(0.12)
    static let star = Color(red: 0.98, green: 0.70, blue: 0.10)         // цвет рейтинга-звезды
    static let danger = Color(red: 0.85, green: 0.20, blue: 0.16)       // заливки и иконки ошибок
    static let dangerInk = Color(red: 0.75, green: 0.15, blue: 0.12)    // текст ошибок: 4.8:1 на своей плашке

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
    /// Плотная заливка: белый текст на ней читается.
    let color: Color
    /// Мягкая плашка того же тона — невыбранные чипы и подложки.
    var tint: Color { color.opacity(0.13) }
}

enum Categories {
    /// Канонические категории: ключ → как показать. Держим в одном месте с бэкендом
    /// (`app/core/categories.py`) — там тот же список для нормализации того, что
    /// человек вписал руками.
    /// Цвета в одном тональном регистре: одинаковая светлота, разный тон. Так белый
    /// текст читается на любой плашке, а сами цвета на бумаге не скачут по яркости —
    /// картинка получается цветной, но не пёстрой.
    static let map: [String: CategoryStyle] = [
        "walk": .init(title: "Прогулка", icon: "figure.walk", color: Color(red: 0.03, green: 0.52, blue: 0.46)),
        "sport": .init(title: "Спорт", icon: "figure.run", color: Color(red: 0.10, green: 0.53, blue: 0.31)),
        "tennis": .init(title: "Спорт", icon: "figure.tennis", color: Color(red: 0.10, green: 0.53, blue: 0.31)),
        "watersport": .init(title: "Вода", icon: "drop.fill", color: Color(red: 0.00, green: 0.43, blue: 0.96)),
        "bike": .init(title: "Велосипед", icon: "bicycle", color: Color(red: 0.08, green: 0.52, blue: 0.45)),
        "gym": .init(title: "Зал", icon: "dumbbell.fill", color: Color(red: 0.26, green: 0.51, blue: 0.34)),
        "yoga": .init(title: "Йога", icon: "figure.mind.and.body", color: Color(red: 0.50, green: 0.37, blue: 0.85)),
        "ski": .init(title: "Лыжи и сноуборд", icon: "figure.skiing.downhill", color: Color(red: 0.08, green: 0.47, blue: 0.79)),
        "fishing": .init(title: "Рыбалка", icon: "fish.fill", color: Color(red: 0.12, green: 0.50, blue: 0.60)),
        "music": .init(title: "Музыка", icon: "music.note", color: Color(red: 0.47, green: 0.34, blue: 1.00)),
        "concert": .init(title: "Концерт", icon: "music.mic", color: Color(red: 0.47, green: 0.34, blue: 1.00)),
        "party": .init(title: "Вечеринка", icon: "party.popper.fill", color: Color(red: 0.84, green: 0.16, blue: 0.55)),
        "dance": .init(title: "Танцы", icon: "figure.dance", color: Color(red: 0.78, green: 0.22, blue: 0.67)),
        "boardgames": .init(title: "Настолки", icon: "die.face.5.fill", color: Color(red: 0.64, green: 0.41, blue: 0.02)),
        "videogames": .init(title: "Видеоигры", icon: "gamecontroller.fill", color: Color(red: 0.38, green: 0.40, blue: 0.91)),
        "quiz": .init(title: "Квиз", icon: "questionmark.circle.fill", color: Color(red: 0.68, green: 0.39, blue: 0.06)),
        "food": .init(title: "Еда", icon: "fork.knife", color: Color(red: 0.85, green: 0.23, blue: 0.07)),
        "bar": .init(title: "Бар", icon: "wineglass.fill", color: Color(red: 0.73, green: 0.23, blue: 0.35)),
        "coffee": .init(title: "Кофе", icon: "cup.and.saucer.fill", color: Color(red: 0.60, green: 0.42, blue: 0.26)),
        "cinema": .init(title: "Кино", icon: "film.fill", color: Color(red: 0.34, green: 0.34, blue: 0.56)),
        "theatre": .init(title: "Театр", icon: "theatermasks.fill", color: Color(red: 0.71, green: 0.27, blue: 0.42)),
        "museum": .init(title: "Музей", icon: "building.columns.fill", color: Color(red: 0.45, green: 0.41, blue: 0.63)),
        "exhibition": .init(title: "Выставка", icon: "photo.artframe", color: Color(red: 0.52, green: 0.39, blue: 0.73)),
        "festival": .init(title: "Фестиваль", icon: "flag.2.crossed.fill", color: Color(red: 0.79, green: 0.30, blue: 0.10)),
        "photo": .init(title: "Фотопрогулка", icon: "camera.fill", color: Color(red: 0.35, green: 0.47, blue: 0.57)),
        "travel": .init(title: "Поездка", icon: "airplane", color: Color(red: 0.11, green: 0.48, blue: 0.75)),
        "roadtrip": .init(title: "Автопутешествие", icon: "car.fill", color: Color(red: 0.29, green: 0.46, blue: 0.71)),
        "pets": .init(title: "С питомцами", icon: "pawprint.fill", color: Color(red: 0.62, green: 0.42, blue: 0.18)),
        "volunteer": .init(title: "Волонтёрство", icon: "hands.sparkles.fill", color: Color(red: 0.14, green: 0.52, blue: 0.40)),
        "study": .init(title: "Учёба", icon: "book.fill", color: Color(red: 0.37, green: 0.46, blue: 0.66)),
        "other": .init(title: "Другое", icon: "sparkles", color: Theme.accentInk),
    ]

    /// Неизвестный ключ — это своя категория: показываем её текстом как есть.
    static func of(_ key: String?) -> CategoryStyle {
        if let key, let c = map[key.lowercased()] { return c }
        guard let key, !key.isEmpty else {
            return .init(title: "Событие", icon: "sparkles", color: Theme.accentInk)
        }
        return .init(title: key.prefix(1).uppercased() + key.dropFirst(),
                     icon: "sparkles", color: Theme.accentInk)
    }

    /// Первый экран выбора: самое ходовое, чтобы не заставлять листать три десятка чипов.
    static let popular = ["walk", "sport", "food", "bar", "music", "concert",
                          "boardgames", "cinema", "watersport", "bike", "coffee", "party"]

    /// Полный список для экрана «все категории», в порядке объявления.
    static let all = ["walk", "sport", "watersport", "bike", "gym", "yoga", "ski", "fishing",
                      "music", "concert", "party", "dance", "boardgames", "videogames", "quiz",
                      "food", "bar", "coffee", "cinema", "theatre", "museum", "exhibition",
                      "festival", "photo", "travel", "roadtrip", "pets", "volunteer",
                      "study", "other"]

    /// Совместимость со старым кодом выбора.
    static var pickable: [String] { popular }
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
    /// `.solid` — поверх фотографии, `.tinted` — на бумаге, где плотная плашка бьёт по глазам.
    var style: Style = .solid
    enum Style { case solid, tinted }

    var body: some View {
        let c = Categories.of(category)
        HStack(spacing: 5) {
            Image(systemName: c.icon).font(.system(size: compact ? 10 : 12, weight: .bold))
            if !compact {
                Text(c.title.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    // Своя категория бывает длинной — режем, а не ломаем строку.
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .foregroundStyle(style == .solid ? Color.white : c.color)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 5 : 6)
        .background(style == .solid ? c.color : c.tint, in: Capsule())
        .overlay(Capsule().stroke(style == .solid ? .clear : c.color.opacity(0.25), lineWidth: 1))
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
            .background(isEnabled ? Theme.accentInk : Theme.ink.opacity(0.12))
            .foregroundStyle(isEnabled ? .white : Theme.ink2)
            .clipShape(RoundedRectangle(cornerRadius: Radii.sm))
        }
        .disabled(!isEnabled || isLoading)
    }
}

/// Рейтинг показываем только с первого отзыва.
///
/// Ноль или прочерк рядом со звездой читаются как плохая оценка, хотя означают
/// лишь отсутствие истории. Поэтому без отзывов виджет либо пуст, либо (там, где
/// это полезно собеседнику — например в списке заявок) показывает «Новичок».
struct RatingView: View {
    let value: Double?
    let count: Int
    /// Показать пометку «Новичок» вместо пустоты.
    var showsNewcomer: Bool = false

    var body: some View {
        if let value, count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").foregroundStyle(Theme.star).font(.caption2)
                Text(String(format: "%.1f", value))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
                Text("(\(count))").font(.caption2).foregroundStyle(Theme.ink2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Рейтинг \(String(format: "%.1f", value)) из 5, отзывов: \(count)")
        } else if showsNewcomer {
            Text("Новичок")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.secondaryBg, in: Capsule())
                .accessibilityLabel("Новичок, отзывов пока нет")
        }
    }
}

/// Вердикт одного отзыва: оценка звёздами либо отметка о неявке.
///
/// Отличается от `RatingView` тем, что показывает конкретный отзыв, а не репутацию
/// целиком — здесь оценка есть всегда, кроме случая «не пришёл».
struct ReviewVerdict: View {
    let rating: Int?
    var attended: Bool = true

    var body: some View {
        if !attended {
            HStack(spacing: 3) {
                Image(systemName: "person.fill.xmark").font(.system(size: 10, weight: .bold))
                Text("не пришёл").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.danger)
            .accessibilityLabel("Отмечен как не пришедший")
        } else if let rating {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(i <= rating ? Theme.star : Theme.inkMuted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Оценка \(rating) из 5")
        }
    }
}

/// Пометка о неявках. Появляется только когда факт есть — молчание тут лучше нуля.
struct NoShowBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "person.fill.xmark").font(.system(size: 10, weight: .bold))
                Text("не пришёл \(count)×").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.dangerInk)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.danger.opacity(0.10), in: Capsule())
            .accessibilityLabel("Не пришёл \(count) раз")
        }
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
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                    Haptics.tap()
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(i <= rating ? Theme.star : Theme.inkMuted)
                        // Оценка человека не должна зависеть от точности попадания:
                        // сама звезда 20pt, зона нажатия — норматив Apple.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оценка")
        .accessibilityValue("\(rating) из 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if rating < 5 { rating += 1 }
            case .decrement: if rating > 1 { rating -= 1 }
            default: break
            }
        }
    }
}

extension View {
    /// Бумажный фон экрана.
    func paperBackground() -> some View { background(Theme.paper.ignoresSafeArea()) }
    func cardStyle() -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radii.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radii.card, style: .continuous)
                .stroke(Theme.lineStrong, lineWidth: 1))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
