import Foundation
import Testing
@testable import Elva

@Suite("FeedViewModel", .serialized)
@MainActor
struct FeedViewModelTests {
    private static let itemJSON = """
    {"id":"e1","title":"Теннис","category":"sport","day":"2026-07-10",
     "starts_at":null,"ends_at":null,"time_disclosed":false,
     "latitude":55.7,"longitude":37.6,"address":null,"map_url":null,
     "cover_url":null,"photo_urls":[],"distance_km":1.2,
     "participants_current":1,"participants_max":4,"price":null,"price_split":"free",
     "status":"open","organizer":{"id":"u1","name":"Орг","avatar_url":null,"rating_avg":4.5}}
    """

    init() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "feed.manualCity")
    }

    private func makeVM() -> (FeedViewModel, TokenStore) {
        let store = TokenStore()
        store.save(access: "acc", refresh: "ref")
        let api = APIClient(base: URL(string: "http://unit.test/api/v1")!,
                            tokenStore: store, session: MockURLProtocol.makeSession())
        let vm = FeedViewModel()
        vm.configure(api)
        return (vm, store)
    }

    @Test("В режиме «моё местоположение» refresh передаёт координаты в запрос")
    func refreshLoadsItems() async throws {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[\#(Self.itemJSON)],"next_cursor":null}"#) }

        // Лента по умолчанию не привязана к городу, поэтому режим задаём явно:
        // координаты уходят только когда человек сам сузил выдачу.
        vm.select(.nearMe)
        vm.setCoordinate(lat: 59.93, lng: 30.33)
        await vm.refresh()

        #expect(vm.items.count == 1)
        #expect(vm.items.first?.title == "Теннис")
        #expect(vm.errorText == nil)
        let url = MockURLProtocol.requests.last?.url?.absoluteString ?? ""
        #expect(url.contains("lat=59.93"))
        #expect(url.contains("lng=30.33"))
    }

    @Test("Ошибка сервера попадает в errorText, список не падает")
    func serverErrorSurfaced() async {
        let (vm, store) = makeVM()
        defer { store.clear() }
        MockURLProtocol.handler = { _ in
            (500, #"{"error":{"code":"http_error","message":"Внутренняя ошибка"}}"#)
        }
        await vm.refresh()
        #expect(vm.items.isEmpty)
        #expect(vm.errorText == "Внутренняя ошибка")
    }

    @Test("Ручной город приоритетнее GPS и переживает пересоздание")
    func manualCityWinsAndPersists() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.manualCity")
            UserDefaults.standard.removeObject(forKey: "feed.scope")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        let sochi = City(name: "Сочи", latitude: 43.6028, longitude: 39.7342)
        vm.select(.city(sochi))
        vm.setCoordinate(lat: 55.75, lng: 37.61)   // GPS должен игнорироваться
        #expect(vm.latitude == sochi.latitude)
        #expect(vm.longitude == sochi.longitude)

        // Новый экземпляр читает сохранённый город из UserDefaults
        let vm2 = FeedViewModel()
        #expect(vm2.manualCity == sochi)
        #expect(vm2.latitude == sochi.latitude)

        // Сброс на геолокацию
        vm.select(.nearMe)
        #expect(vm.manualCity == nil)
        #expect(FeedViewModel().scope == .nearMe)
    }

    @Test("По умолчанию лента показывает все города")
    func everywhereIsDefault() async {
        UserDefaults.standard.removeObject(forKey: "feed.scope")
        UserDefaults.standard.removeObject(forKey: "feed.manualCity")
        #expect(FeedViewModel().scope == .everywhere)
    }

    @Test("В режиме «все города» координаты в запрос не уходят")
    func everywhereSendsNoCoordinates() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
        }
        // Ревью велось из Купертино, а события были в Москве: с координатами
        // лента оказывалась пустой. Проверяем, что «все города» их не шлёт.
        var seen: URL?
        MockURLProtocol.handler = { req in
            seen = req.url
            return (200, #"{"items":[],"next_cursor":null}"#)
        }
        vm.select(.everywhere)
        await vm.refresh()

        let query = seen?.query ?? ""
        #expect(!query.contains("lat="))
        #expect(!query.contains("lng="))
        #expect(!query.contains("radius_km="))
    }

    @Test("С выбранным городом координаты по-прежнему уходят")
    func cityStillSendsCoordinates() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
            UserDefaults.standard.removeObject(forKey: "feed.manualCity")
        }
        var seen: URL?
        MockURLProtocol.handler = { req in
            seen = req.url
            return (200, #"{"items":[],"next_cursor":null}"#)
        }
        vm.select(.city(City(name: "Сочи", latitude: 43.6028, longitude: 39.7342)))
        await vm.refresh()

        let query = seen?.query ?? ""
        #expect(query.contains("lat=43.6028"))
        #expect(query.contains("lng=39.7342"))
    }

    @Test("Геопозиция в городе из списка открывает этот город")
    func locationInsideKnownCityPicksIt() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
            UserDefaults.standard.removeObject(forKey: "feed.manualCity")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        vm.setCoordinate(lat: 59.93, lng: 30.33)          // Санкт-Петербург
        #expect(vm.scope == .city(City(name: "Санкт-Петербург",
                                       latitude: 59.9343, longitude: 30.3351)))
    }

    @Test("Пригород считается своим городом")
    func suburbCountsAsCity() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
            UserDefaults.standard.removeObject(forKey: "feed.manualCity")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        // Химки: за границей города, но вечером человек поедет в Москву.
        vm.setCoordinate(lat: 55.89, lng: 37.43)
        #expect(vm.manualCity?.name == "Москва")
    }

    @Test("Вне списка городов остаются все города")
    func locationOutsideListKeepsEverywhere() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        // Купертино: именно отсюда шло ревью App Store и лента была пустой.
        vm.setCoordinate(lat: 37.3349, lng: -122.0090)
        #expect(vm.scope == .everywhere)
    }

    @Test("Собственный выбор сильнее геопозиции")
    func explicitChoiceBeatsLocation() async {
        let (vm, store) = makeVM()
        defer {
            store.clear()
            UserDefaults.standard.removeObject(forKey: "feed.scope")
            UserDefaults.standard.removeObject(forKey: "feed.manualCity")
        }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        vm.select(.everywhere)
        vm.setCoordinate(lat: 59.93, lng: 30.33)          // сидим в Петербурге
        #expect(vm.scope == .everywhere)                  // но выбрали «все города»
    }
}
