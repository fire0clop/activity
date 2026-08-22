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
        guard !wasSeen, !steps.isEmpty else { return }
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

// MARK: - Подсветка

/// Затемнение с вырезом вокруг элемента и пояснением рядом.
struct TourOverlay: View {
    let step: TourStep
    /// Кадр подсвечиваемого элемента; nil — шаг без привязки к элементу.
    let target: CGRect?
    let index: Int
    let total: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var hole: CGRect? {
        target?.insetBy(dx: -step.padding, dy: -step.padding)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                dimming(in: proxy.size)
                if let hole { ring(hole) }
                callout(in: proxy.size)
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
        .onAppear { if !reduceMotion { pulse = true } }
        // Тап мимо пояснения — следующий шаг: промахнуться по кнопке нельзя.
        .contentShape(Rectangle())
        .onTapGesture { onNext() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Обучение, шаг \(index + 1) из \(total): \(step.title)")
    }

    /// Затемнение с дыркой. Рисуется одной фигурой по чётно-нечётному правилу —
    /// иначе край выреза получается с полупрозрачной каймой.
    private func dimming(in size: CGSize) -> some View {
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
        .animation(.easeInOut(duration: 0.28), value: hole?.origin.y)
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
            .scaleEffect(pulse ? 1.04 : 1)
            .opacity(pulse ? 0.75 : 1)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .allowsHitTesting(false)
    }

    private func callout(in size: CGSize) -> some View {
        let width = min(size.width - 40, 340)
        let below = (hole?.maxY ?? size.height / 2) + 16
        let showsBelow = below + 190 < size.height
        let y = showsBelow ? below : max(60, (hole?.minY ?? size.height / 2) - 190)

        return VStack(alignment: .leading, spacing: 10) {
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
                Spacer()
                if index < total - 1 {
                    Button("Пропустить", action: onSkip)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
                }
                Button(action: onNext) {
                    Text(index == total - 1 ? "Понятно" : "Дальше")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accentInk, in: Capsule())
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.lineStrong))
        .shadow(color: Theme.ink.opacity(0.25), radius: 20, y: 8)
        .position(x: size.width / 2, y: y + 95)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
    }
}

// MARK: - Подключение к экрану

extension View {
    /// Навесить обучение на экран: подсветка рисуется поверх, по якорям.
    func tour(_ controller: TourController) -> some View {
        overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let step = controller.current {
                    TourOverlay(
                        step: step,
                        target: anchors[step.id].map { proxy[$0] },
                        index: controller.stepIndex,
                        total: controller.steps.count,
                        onNext: { controller.next() },
                        onSkip: { controller.finish() }
                    )
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: controller.stepIndex)
        }
    }
}
