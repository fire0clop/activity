import Foundation
import Testing
@testable import Elva

@Suite("PushRoute")
struct PushRouteTests {
    @Test("event_id -> маршрут на событие")
    func eventRoute() {
        let route = PushRoute.from(userInfo: ["event_id": "e-42", "aps": [:]])
        #expect(route == .event(id: "e-42"))
    }

    @Test("conversation_id приоритетнее event_id (пуш о сообщении ведёт в чат)")
    func conversationBeatsEvent() {
        let route = PushRoute.from(userInfo: ["event_id": "e-1", "conversation_id": "c-7"])
        #expect(route == .conversation(id: "c-7"))
    }

    @Test("Пуш без данных не даёт маршрута")
    func noRoute() {
        #expect(PushRoute.from(userInfo: ["aps": ["alert": "hi"]]) == nil)
    }
}

@Suite("Универсальные ссылки")
struct UniversalLinkTests {
    @Test("Ссылка /e/<id> ведёт на событие")
    func eventLink() throws {
        let url = try #require(URL(string: "https://event-serv.ru/e/3fa85f64-5717-4562-b3fc-2c963f66afa6"))
        #expect(PushRoute.from(url: url) == .event(id: "3fa85f64-5717-4562-b3fc-2c963f66afa6"))
    }

    @Test("Чужие и неполные адреса игнорируются")
    func foreignLinks() throws {
        for bad in ["https://event-serv.ru/", "https://event-serv.ru/e/",
                    "https://event-serv.ru/privacy", "https://event-serv.ru/e/abc/extra"] {
            let url = try #require(URL(string: bad))
            #expect(PushRoute.from(url: url) == nil, "не должен разбираться: \(bad)")
        }
    }
}
