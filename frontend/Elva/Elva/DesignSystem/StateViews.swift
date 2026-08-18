import SwiftUI

/// Пустое состояние: иконка в мягком круге + заголовок + подзаголовок + опциональное действие.
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 88, height: 88)
                Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.accent)
            }
            Text(title).font(.serifTitle(20, weight: .bold)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Theme.accent).clipShape(Capsule())
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// Состояние ошибки с повтором.
struct ErrorState: View {
    var title: String = "Не удалось загрузить"
    var subtitle: String = "Проверьте соединение и попробуйте снова."
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.system(size: 38)).foregroundStyle(Theme.ink2)
            Text(title).font(.serifTitle(19, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button(action: retry) {
                Text("Повторить").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Theme.accentSoft).clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// Скелетон карточки ленты — мягкое мерцание на время загрузки (вместо голого спиннера).
struct SkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 150)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.line).frame(width: 180, height: 18)
                RoundedRectangle(cornerRadius: 6).fill(Theme.line).frame(width: 120, height: 12)
            }
            .padding(14)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radii.card))
        .overlay(RoundedRectangle(cornerRadius: Radii.card).stroke(Theme.line))
        .opacity(shimmer ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}

/// Секция формы в бумажной карточке: серифный строчный заголовок + поля (разделяй FormDivider).
struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.serifTitle(19, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
    }
}

/// Хайрлайн-разделитель между полями внутри FormSection.
struct FormDivider: View {
    var body: some View { Divider().background(Theme.line) }
}

/// Единый стиль поля ввода на бумажном фоне (auth-экраны).
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding().background(Theme.secondaryBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// Ряд метрик с вертикальными разделителями — единый компонент для детали события и профиля.
struct MetricsRow: View {
    struct Metric { let value: String; let label: String }
    let items: [Metric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(Theme.line).frame(width: 1, height: 32) }
                VStack(spacing: 4) {
                    Text(item.value).font(.serifTitle(20, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(item.label).font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14).frame(maxWidth: .infinity).cardStyle()
    }
}
