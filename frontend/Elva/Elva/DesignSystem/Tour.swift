import SwiftUI

// MARK: - Якоря

/// Экран сообщает наверх, где лежат его ключевые элементы. Подсветка рисуется по
/// реальным координатам, поэтому не разъедется от смены шрифта, языка или устройства.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Пометить элемент как объясняемый в обучении.
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Содержание

struct TourStep: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    /// Насколько расширить вырез вокруг элемента.
    var padding: CGFloat = 8
    /// Форма выреза: у круглых кнопок прямоугольная рамка выглядит небрежно.
    var shape: Shape = .capsule

    enum Shape: Equatable { case capsule, circle, rounded }
}

/// Обучение показывается один раз и заново — только по просьбе из профиля.
@MainActor
final class TourController: ObservableObject {
    @Published private(set) var stepIndex = 0
    @Published private(set) var isActive = false

    let steps: [TourStep]
    private let storageKey: String

    init(steps: [TourStep], storageKey: String) {
        self.steps = steps
        self.storageKey = storageKey
    }

    var current: TourStep? { isActive && steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var isLast: Bool { stepIndex >= steps.count - 1 }
    var wasSeen: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// Запустить, если человек этого ещё не видел.
    func startIfNeeded() {
        // Идущее обучение не начинаем заново: иначе возврат на ленту откидывал бы
        // человека на первый шаг.
        guard !isActive, !wasSeen, !steps.isEmpty else { return }
        stepIndex = 0
        isActive = true
    }

    func restart() {
        stepIndex = 0
        isActive = true
    }

    func next() {
        if isLast { finish() } else { stepIndex += 1; Haptics.tap() }
    }

    func finish() {
        isActive = false
        UserDefaults.standard.set(true, forKey: storageKey)
    }
}

/// Содержание обучения по ленте. Живёт отдельно от экрана, потому что показывает
/// его корневой контейнер: подсветка обязана накрывать и таб-бар, а он лежит выше
/// вкладки — изнутри вкладки его не перекрыть, и кнопки обучения оказывались под ним.
enum TourLayout {
    /// Якорь на область вкладки без панели снизу. Панель вкладок в iOS 26 плавающая
    /// и живёт в своём слое поверх любых наложений — накрыть её нельзя, а кнопки
    /// пояснения, заехавшие под неё, просто перестают нажиматься.
    static let content = "tour.content"
}

enum FeedTour {
    static let storageKey = "tour.feed.v1"

    static let steps: [TourStep] = [
        TourStep(
            id: "tour.pages",
            title: "Здесь три ленты",
            text: "«Активности» затевают люди — к ним можно присоединиться. «Афиша» идёт в городе сама по себе. «Хочу» — чужие желания, которые пока никто не взял на себя. Листаются пальцем.",
            padding: 6, shape: .capsule
        ),
        TourStep(
            id: "tour.filters",
            title: "Сузить выдачу",
            text: "Дата, категория и «только бесплатные» — в одном окне. Цифра на кнопке показывает, сколько фильтров включено, чтобы пустая лента не выглядела концом света.",
            shape: .capsule
        ),
        TourStep(
            id: "tour.map",
            title: "То же самое на карте",
            text: "Круглые цветные метки — сборы людей, тёмные квадратные — афиша. Удобно, когда важнее «что рядом со мной», чем «что сегодня».",
            padding: 4, shape: .circle
        ),
        TourStep(
            id: "tour.create",
            title: "Позвать компанию",
            text: "Придумали что-то — заведите событие: название, время, место. Люди рядом увидят его в ленте и откликнутся, а чат соберётся сам. На вкладке «Хочу» эта же кнопка заявляет желание, ни к чему не обязывая.",
            padding: 4, shape: .circle
        ),
    ]
}

// MARK: - Подсветка

/// Затемнение с вырезом вокруг элемента и пояснением рядом.
struct TourOverlay: View {
    let step: TourStep
    /// Кадр подсвечиваемого элемента; nil — шаг без привязки к элементу.
    let target: CGRect?
    /// Нижняя граница, ниже которой пояснение размещать нельзя: там панель вкладок.
    let bottomLimit: CGFloat
    let index: Int
    let total: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// Вырез вокруг элемента с полем, которое влезает в экран.
    ///
    /// Раньше расширенная рамка просто обрезалась о границу экрана. У кнопки,
    /// прижатой к левому краю, слева срезалось больше, чем справа, и кольцо
    /// выглядело съехавшим. Теперь поле сжимается одинаково со всех сторон —
    /// кольцо остаётся симметричным, просто становится уже.
    private func hole(in size: CGSize) -> CGRect? {
        guard let target else { return nil }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
        let room = min(step.padding,
                       target.minX - bounds.minX, bounds.maxX - target.maxX,
                       target.minY - bounds.minY, bounds.maxY - target.maxY)
        return target.insetBy(dx: -max(room, 0), dy: -max(room, 0))
    }

    var body: some View {
        GeometryReader { proxy in
            let cut = hole(in: proxy.size)
            ZStack(alignment: .topLeading) {
                // Тап мимо пояснения закрывает обучение. Это не «следующий шаг»:
                // такой жест срабатывал вместе с кнопкой и проскакивал шаг. И это
                // не глухой слой: пока подсветка висит поверх всего приложения,
                // без выхода наружу человек оказывался заперт — вкладки нажимались,
                // но не переключались, и это читалось как «ничего не работает».
                dimming(cut, in: proxy.size)
                    .contentShape(Rectangle())
                    .onTapGesture { onSkip() }
                if let cut { ring(cut) }
                calloutLayout(cut, in: proxy.size)
                    .frame(width: proxy.size.width, height: max(bottomLimit, 200), alignment: .top)
                    .zIndex(1)
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
        .onAppear { pulse = true }
    }

    /// Затемнение с дыркой. Рисуется одной фигурой по чётно-нечётному правилу —
    /// иначе край выреза получается с полупрозрачной каймой.
    private func dimming(_ hole: CGRect?, in size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole {
                switch step.shape {
                case .circle: path.addEllipse(in: hole)
                case .capsule: path.addRoundedRect(in: hole, cornerSize: CGSize(width: hole.height / 2,
                                                                                height: hole.height / 2))
                case .rounded: path.addRoundedRect(in: hole, cornerSize: CGSize(width: 18, height: 18))
                }
            }
        }
        .fill(Theme.ink.opacity(0.62), style: FillStyle(eoFill: true))
    }

    @ViewBuilder
    private func ring(_ rect: CGRect) -> some View {
        let shape: AnyShape = switch step.shape {
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        shape
            .stroke(Theme.accent, lineWidth: 2.5)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            // Однократное проявление вместо вечной пульсации. Бесконечная анимация
            // не даёт экрану перейти в состояние покоя: система считает элементы под
            // ней недоступными для нажатия, и автотесты на такой экран не работают.
            .scaleEffect(pulse ? 1 : 1.08)
            .opacity(pulse ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: pulse)
            .allowsHitTesting(false)
    }

    /// Пояснение прижимается к краю экрана, противоположному подсветке.
    ///
    /// Раньше положение вычислялось от подсвечиваемого элемента, и высота карточки
    /// оказывалась зажата: длинный текст сжимался, а низ с кнопками срезался — со
    /// стороны это выглядело как «кнопка не нажимается». Теперь высота карточки
    /// свободна, и её низ гарантированно на экране: что именно подсвечено, и так
    /// видно по кольцу.
    private func calloutLayout(_ hole: CGRect?, in size: CGSize) -> some View {
        let highlightIsHigh = (hole?.midY ?? size.height / 2) < size.height / 2
        return VStack(spacing: 0) {
            if highlightIsHigh {
                Spacer(minLength: 24)
                callout
            } else {
                callout
                Spacer(minLength: 24)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title).font(.serifTitle(21, weight: .bold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.text).font(.system(size: 15)).foregroundStyle(Theme.ink2)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                // Точки-шаги: видно, сколько осталось, — без этого обучение
                // ощущается бесконечным.
                HStack(spacing: 5) {
                    ForEach(0..<total, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.accent : Theme.line)
                            .frame(width: i == index ? 16 : 6, height: 6)
                    }
                }
                Spacer(minLength: 8)
                if index < total - 1 {
                    Button("Пропустить", action: onSkip)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tour.skip")
                }
                Button(action: onNext) {
                    Text(index == total - 1 ? "Понятно" : "Дальше")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accentInk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tour.next")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.lineStrong))
        .shadow(color: Theme.ink.opacity(0.25), radius: 20, y: 8)
    }
}

// MARK: - Подключение к экрану

/// Носитель подсветки.
///
/// Отдельный вид с `@ObservedObject` нужен по существу: `overlayPreferenceValue`
/// пересчитывает своё содержимое при изменении ЯКОРЕЙ, а не состояния. Якоря
/// после первой отрисовки постоянны, поэтому смена шага не доходила до экрана:
/// первый шаг показывался, а нажатие «Дальше» уже ничего не меняло.
private struct TourHost: View {
    @ObservedObject var controller: TourController
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let step = controller.current {
                TourOverlay(
                    step: step,
                    target: anchors[step.id].map { proxy[$0] },
                    bottomLimit: anchors[TourLayout.content].map { proxy[$0].maxY }
                        ?? proxy.size.height,
                    index: controller.stepIndex,
                    total: controller.steps.count,
                    onNext: { controller.next() },
                    onSkip: { controller.finish() }
                )
            }
        }
        .ignoresSafeArea()
        // Одна анимация на весь слой: вырез и пояснение раньше ехали по разным
        // кривым и с разной длительностью — со стороны это выглядело рассинхроном.
        .animation(.easeInOut(duration: 0.3), value: controller.stepIndex)
    }
}

extension View {
    /// Навесить обучение на экран: подсветка рисуется поверх, по якорям.
    func tour(_ controller: TourController) -> some View {
        overlayPreferenceValue(TourAnchorKey.self) { anchors in
            TourHost(controller: controller, anchors: anchors)
        }
    }
}
