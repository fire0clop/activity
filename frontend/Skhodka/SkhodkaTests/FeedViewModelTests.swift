import Foundation
import Testing
@testable import Skhodka

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

    @Test("refresh загружает события и передаёт координаты в запрос")
    func refreshLoadsItems() async throws {
        let (vm, store) = makeVM()
        defer { store.clear() }
        MockURLProtocol.handler = { _ in (200, #"{"items":[\#(Self.itemJSON)],"next_cursor":null}"#) }

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
        defer { store.clear(); UserDefaults.standard.removeObject(forKey: "feed.manualCity") }
        MockURLProtocol.handler = { _ in (200, #"{"items":[],"next_cursor":null}"#) }

        let sochi = City(name: "Сочи", latitude: 43.6028, longitude: 39.7342)
        vm.selectCity(sochi)
        vm.setCoordinate(lat: 55.75, lng: 37.61)   // GPS должен игнорироваться
        #expect(vm.latitude == sochi.latitude)
        #expect(vm.longitude == sochi.longitude)

        // Новый экземпляр читает сохранённый город из UserDefaults
        let vm2 = FeedViewModel()
        #expect(vm2.manualCity == sochi)
        #expect(vm2.latitude == sochi.latitude)

        // Сброс на геолокацию
        vm.selectCity(nil)
        #expect(vm.manualCity == nil)
        #expect(FeedViewModel().manualCity == nil)
    }
}
