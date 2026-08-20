import SwiftUI

/// Набор фильтров ленты. Один тип на все три страницы — иначе они начнут
/// расходиться в мелочах и читаться как разные экраны.
struct FeedFilters: Equatable {
    var category: String = ""
    /// nil — любая дата.
    var when: String?
    var freeOnly: Bool = false

    var isEmpty: Bool { category.isEmpty && when == nil && !freeOnly }

    /// Сколько фильтров включено — цифра на кнопке, чтобы человек видел,
    /// что выдача сужена, не открывая окно.
    var activeCount: Int {
        (category.isEmpty ? 0 : 1) + (when == nil ? 0 : 1) + (freeOnly ? 1 : 0)
    }

    mutating func reset() {
        category = ""
        when = nil
        freeOnly = false
    }
}

/// Кнопка «Фильтры» со счётчиком.
///
/// Раньше фильтры лежали горизонтальными лентами прямо на странице. Внутри
/// листаемых страниц это давало две беды сразу: пролистывание чипов уводило на
/// соседнюю страницу, а сбросить категорию было нечем — «показать всё» просто
/// не существовало как действие.
struct FiltersButton: View {
    let filters: FeedFilters
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .bold))
                Text("Фильтры").font(.system(size: 14, weight: .semibold))
                if filters.activeCount > 0 {
                    Text("\(filters.activeCount)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Theme.accentInk, in: Circle())
                }
            }
            .foregroundStyle(filters.isEmpty ? Theme.ink : Theme.accentInk)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(filters.isEmpty ? Theme.surface : Theme.accentSoft, in: Capsule())
            .overlay(Capsule().stroke(filters.isEmpty ? Theme.lineStrong : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filters.activeCount > 0
                            ? "Фильтры, включено: \(filters.activeCount)" : "Фильтры")
    }
}

/// Окно фильтров: дата, категория и бесплатность в одном месте.
struct FiltersSheet: View {
    @Binding var filters: FeedFilters
    /// «Бесплатно» осмысленно не везде: у желаний цены нет вовсе.
    var showsFree: Bool = true
    var onApply: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft = FeedFilters()

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    private static let dates: [(title: String, value: String?)] = [
        ("Любая дата", nil), ("Сегодня", "today"),
        ("Завтра", "tomorrow"), ("Выходные", "weekend"), ("На неделе", "week"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Когда") {
                        FlowRow(spacing: 8) {
                            ForEach(Self.dates, id: \.title) { option in
                                pill(option.title, active: draft.when == option.value) {
                                    draft.when = option.value
                                }
                            }
                        }
                    }

                    if showsFree {
                        section("Деньги") {
                            Toggle("Только бесплатные", isOn: $draft.freeOnly)
                                .font(.system(size: 16)).tint(Theme.accent)
                        }
                    }

                    section("Категория") {
                        LazyVGrid(columns: cols, spacing: 8) {
                            // «Все категории» первой — без неё выбранную категорию
                            // нечем снять, и человек застревает в узком срезе.
                            allCategoriesTile
                            ForEach(Categories.all, id: \.self) { tile($0) }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сбросить") { draft.reset() }
                        .disabled(draft.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Показать") {
                        filters = draft
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = filters }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.serifTitle(19, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.leading, 4)
            content()
        }
    }

    private func pill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(active ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Theme.lineStrong))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var allCategoriesTile: some View {
        let selected = draft.category.isEmpty
        return Button {
            draft.category = ""
            Haptics.tap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? .white : Theme.ink2)
                    .frame(width: 26, height: 26)
                    .background(selected ? Color.white.opacity(0.22) : Theme.secondaryBg, in: Circle())
                Text("Все категории").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Theme.ink : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Radii.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radii.sm, style: .continuous)
                .stroke(selected ? .clear : Theme.lineStrong))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ key: String) -> some View {
        let c = Categories.of(key)
        let selected = draft.category == key
        return Button {
            draft.category = selected ? "" : key
            Haptics.tap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: c.icon).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? .white : c.color)
                    .frame(width: 26, height: 26)
                    .background(selected ? Color.white.opacity(0.22) : c.tint, in: Circle())
                Text(c.title).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? .white : Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? c.color : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Radii.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radii.sm, style: .continuous)
                .stroke(selected ? .clear : c.color.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Простая раскладка «в строку с переносом»: пилюли дат не помещаются в ряд,
/// а горизонтальная прокрутка внутри листаемых страниц перехватывает свайп.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
