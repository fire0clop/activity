import SwiftUI

/// Выбор города для ленты — когда геолокация запрещена или хочется посмотреть другой город.
struct CityPickerView: View {
    let selected: City?
    let locationDenied: Bool
    var onSelect: (City?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    static let cities: [City] = [
        City(name: "Москва", latitude: 55.7558, longitude: 37.6173),
        City(name: "Санкт-Петербург", latitude: 59.9343, longitude: 30.3351),
        City(name: "Новосибирск", latitude: 55.0084, longitude: 82.9357),
        City(name: "Екатеринбург", latitude: 56.8389, longitude: 60.6057),
        City(name: "Казань", latitude: 55.7963, longitude: 49.1088),
        City(name: "Нижний Новгород", latitude: 56.2965, longitude: 43.9361),
        City(name: "Челябинск", latitude: 55.1644, longitude: 61.4368),
        City(name: "Самара", latitude: 53.1959, longitude: 50.1002),
        City(name: "Омск", latitude: 54.9885, longitude: 73.3242),
        City(name: "Ростов-на-Дону", latitude: 47.2357, longitude: 39.7015),
        City(name: "Уфа", latitude: 54.7388, longitude: 55.9721),
        City(name: "Красноярск", latitude: 56.0153, longitude: 92.8932),
        City(name: "Воронеж", latitude: 51.6608, longitude: 39.2003),
        City(name: "Пермь", latitude: 58.0105, longitude: 56.2502),
        City(name: "Волгоград", latitude: 48.7080, longitude: 44.5133),
        City(name: "Краснодар", latitude: 45.0355, longitude: 38.9753),
        City(name: "Сочи", latitude: 43.6028, longitude: 39.7342),
        City(name: "Тюмень", latitude: 57.1522, longitude: 65.5272),
    ]

    private var filtered: [City] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? Self.cities : Self.cities.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if locationDenied {
                    Text("Доступ к геолокации выключен — выбери город, чтобы видеть события рядом. Включить геолокацию можно в Настройках.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                        .listRowBackground(Theme.accentSoft)
                }
                Button {
                    onSelect(nil); dismiss()
                } label: {
                    HStack {
                        Label("Моё местоположение", systemImage: "location.fill")
                            .foregroundStyle(locationDenied ? Theme.ink2 : Theme.ink)
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                }
                .disabled(locationDenied)

                ForEach(filtered) { city in
                    Button {
                        onSelect(city); dismiss()
                    } label: {
                        HStack {
                            Text(city.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if selected == city { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
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
