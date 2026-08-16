import SwiftUI

/// Выбор категории: ходовые чипы сразу, полный список и своя категория — по кнопке.
///
/// Тридцать чипов в строку никто листать не станет, поэтому на виду дюжина самых
/// частых, а всё остальное — на отдельном экране. Своя категория там же: продукт
/// про любое занятие, и заранее перечислить все занятия невозможно.
struct CategoryPicker: View {
    @Binding var selection: String
    var showsAllButton: Bool = true

    @State private var showAll = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Своя категория, уже выбранная, должна остаться на виду.
                if !selection.isEmpty && !Categories.popular.contains(selection) {
                    chip(selection)
                }
                ForEach(Categories.popular, id: \.self) { chip($0) }
                if showsAllButton {
                    Button { showAll = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                            Text("Ещё").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.secondaryBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .sheet(isPresented: $showAll) {
            AllCategoriesView(selection: $selection)
        }
    }

    private func chip(_ key: String) -> some View {
        let c = Categories.of(key)
        let selected = selection == key
        return Button {
            selection = selected ? "" : key
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: c.icon).font(.system(size: 11, weight: .bold))
                Text(c.title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? c.color : Theme.secondaryBg, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Полный список категорий плюс поле для своей.
struct AllCategoriesView: View {
    @Binding var selection: String
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var custom = ""
    /// Что уже вписывали другие — чтобы «настольный теннис» не расщепился на пять написаний.
    @State private var used: [CategoryItem] = []

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSection(title: "Своя категория") {
                        TextField("Например: настольный теннис", text: $custom)
                            .autocorrectionDisabled()
                        if !trimmedCustom.isEmpty {
                            Button {
                                selection = trimmedCustom
                                Haptics.success()
                                dismiss()
                            } label: {
                                Label("Выбрать «\(trimmedCustom)»", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.accentInk)
                            }
                        }
                        Text("Категория пишется строчными и объединяется с такими же — так поиск по ней остаётся осмысленным.")
                            .font(.footnote).foregroundStyle(Theme.ink2)
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("УЖЕ ИСПОЛЬЗУЮТ")
                                .font(.system(size: 12, weight: .heavy)).tracking(1)
                                .foregroundStyle(Theme.ink2).padding(.leading, 4)
                            LazyVGrid(columns: cols, spacing: 8) {
                                ForEach(suggestions, id: \.key) { item in
                                    tile(item.key, subtitle: "\(item.usage)")
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ВСЕ КАТЕГОРИИ")
                            .font(.system(size: 12, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.ink2).padding(.leading, 4)
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(Categories.all, id: \.self) { tile($0, subtitle: nil) }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
            }
            .task { await loadUsed() }
        }
    }

    private var trimmedCustom: String {
        custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Чужие категории, которых нет в каноническом списке.
    private var suggestions: [CategoryItem] {
        used.filter { !$0.isCanonical && $0.usage > 0 }.prefix(8).map { $0 }
    }

    private func tile(_ key: String, subtitle: String?) -> some View {
        let c = Categories.of(key)
        let selected = selection == key
        return Button {
            selection = key
            Haptics.tap()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: c.icon).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? .white : c.color).frame(width: 20)
                Text(c.title).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? .white : Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? .white.opacity(0.8) : Theme.ink2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? c.color : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Radii.sm))
            .overlay(RoundedRectangle(cornerRadius: Radii.sm)
                .stroke(selected ? .clear : Theme.line))
        }
        .buttonStyle(.plain)
    }

    private func loadUsed() async {
        if let resp: CategoriesResponse = try? await auth.api.send(Endpoint(path: "/categories")) {
            used = resp.items
        }
    }
}
