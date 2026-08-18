import SwiftUI

/// Подписки на новые события: пуш, когда рядом или в любимой категории появляется движуха.
struct SubscriptionsView: View {
    /// Текущая точка ленты — по ней создаётся гео-подписка «рядом со мной».
    let latitude: Double
    let longitude: Double
    let locationName: String

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Subscription] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // Форма новой подписки
    @State private var category: String?          // nil = любая категория
    @State private var nearMe = true
    @State private var radiusKm: Double = 10

    private let categories: [(key: String?, title: String)] =
        [(nil, "Любая категория")] + Categories.map
            .map { (Optional($0.key), $0.value.title) }
            .sorted { $0.1 < $1.1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Новая подписка") {
                    Picker("Категория", selection: $category) {
                        ForEach(categories, id: \.key) { c in
                            Text(c.title).tag(c.key)
                        }
                    }
                    Toggle("Только рядом (\(locationName))", isOn: $nearMe)
                    if nearMe {
                        HStack {
                            Text("Радиус")
                            Slider(value: $radiusKm, in: 1...100, step: 1)
                            Text("\(Int(radiusKm)) км").monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    Button("Подписаться") { Task { await create() } }
                        .disabled(category == nil && !nearMe)
                }

                Section("Мои подписки") {
                    if isLoading {
                        ProgressView()
                    } else if items.isEmpty {
                        Text("Пока нет подписок. Подпишись — пришлём пуш, когда появится подходящее событие.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { sub in
                            row(sub)
                        }
                        .onDelete { idx in Task { await delete(at: idx) } }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Подписки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func row(_ sub: Subscription) -> some View {
        HStack(spacing: 10) {
            let style = Categories.of(sub.category)
            Image(systemName: sub.category != nil ? style.icon : "bell.fill")
                .foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.category != nil ? style.title : "Любая категория")
                    .font(.system(size: 15, weight: .semibold))
                if sub.latitude != nil {
                    Text("В радиусе \(Int(sub.radiusKm)) км")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Везде").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: SubscriptionsResponse = try await auth.api.send(Endpoint(path: "/subscriptions"))
            items = resp.items
        } catch {
            errorText = "Не удалось загрузить подписки"
        }
    }

    private func create() async {
        errorText = nil
        do {
            let _: Subscription = try await auth.api.send(Endpoint(
                path: "/subscriptions", method: .post,
                body: SubscriptionCreateBody(
                    category: category,
                    latitude: nearMe ? latitude : nil,
                    longitude: nearMe ? longitude : nil,
                    radius_km: radiusKm)))
            await load()
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось создать подписку"
        }
    }

    private func delete(at offsets: IndexSet) async {
        for i in offsets {
            let sub = items[i]
            try? await auth.api.sendVoid(Endpoint(path: "/subscriptions/\(sub.id)", method: .delete))
        }
        await load()
    }
}
