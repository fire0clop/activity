import SwiftUI

/// Выбор города для ленты — когда геолокация запрещена или хочется посмотреть другой город.
struct CityPickerView: View {
    let scope: FeedScope
    let locationDenied: Bool
    var onSelect: (FeedScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""


    private var filtered: [City] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? City.all : City.all.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if locationDenied {
                    Text("Доступ к геолокации выключен — выбери город, чтобы видеть события рядом. Включить геолокацию можно в Настройках.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                        .listRowBackground(Theme.accentSoft)
                }
                // Всё подряд — состояние по умолчанию: в пустом городе лента,
                // сужённая до своего района, показывает только заглушку.
                Button {
                    onSelect(.everywhere); dismiss()
                } label: {
                    HStack {
                        Label("Все города", systemImage: "globe")
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if scope == .everywhere {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }

                Button {
                    onSelect(.nearMe); dismiss()
                } label: {
                    HStack {
                        Label("Моё местоположение", systemImage: "location.fill")
                            .foregroundStyle(locationDenied ? Theme.ink2 : Theme.ink)
                        Spacer()
                        if scope == .nearMe {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .disabled(locationDenied)

                ForEach(filtered) { city in
                    Button {
                        onSelect(.city(city)); dismiss()
                    } label: {
                        HStack {
                            Text(city.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if scope == .city(city) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Найти город")
            .navigationTitle("Город")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
