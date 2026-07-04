import Testing
@testable import Skhodka

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
