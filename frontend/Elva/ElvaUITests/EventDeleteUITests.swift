import XCTest

/// Удаление созданного события — до самого конца, глазами человека.
///
/// Жалоба была прямой: «нажимаю удалить и ничего не происходит». Так и было:
/// удаление мягкое (событие получает статус «отменено»), список «Мои события»
/// отменённые не отфильтровывал, а экран закрывал только лист редактирования —
/// под ним оставалась та же карточка. Здесь путь проходится целиком.
final class EventDeleteUITests: XCTestCase {

    private let host = "https://api.event-serv.ru/api/v1"
    private var token: String { ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? "" }
    private var title = ""
    private var createdEventID: String?

    /// Событие заводим через API: интерес теста — удаление, а не форма создания.
    private func createEvent() throws {
        title = "Тест удаления \(Int(Date().timeIntervalSince1970))"
        var req = URLRequest(url: URL(string: "\(host)/events")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let starts = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86400))
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": title, "description": "временное событие для проверки удаления",
            "category": "walk", "starts_at": starts,
            "latitude": 55.751, "longitude": 37.618, "address": "Тестовая точка",
            "min_participants": 2, "max_participants": 4,
            "price": 0, "price_split": "free", "auto_accept": true,
        ])

        let done = expectation(description: "событие создано")
        var status = 0
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.createdEventID = json["id"] as? String
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        XCTAssertEqual(status, 201, "Не удалось подготовить событие — проверьте токен")
        XCTAssertNotNil(createdEventID, "Сервер не вернул id события")

        // Событие создаётся на боевом сервере. Если прогон упадёт посередине,
        // оно останется висеть в общей ленте — ровно так тестовый мусор попал
        // на глаза ревьюеру App Store. Убираем через API независимо от исхода.
        // self захватываем ссылкой: id известен только после ответа сервера.
        addTeardownBlock { [token] in
            guard let id = self.createdEventID else { return }
            var req = URLRequest(url: URL(string: "https://api.event-serv.ru/api/v1/events/\(id)")!)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = token
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] =
            ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchArguments += ["-feed.scope", "nearMe",
                                "-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()
        settleAfterLaunch(app)
        return app
    }

    func testDeletedEventDisappearsFromMyEvents() throws {
        try createEvent()
        let app = launchApp()

        XCTAssertTrue(waitForApp(app.buttons["Профиль"]), "Вкладка «Профиль» не появилась")
        tapWhenReady(app.buttons["Профиль"], "вкладка «Профиль»")
        let myEvents = app.staticTexts["Мои события"]
        XCTAssertTrue(myEvents.waitForExistence(timeout: 10), "Профиль не открылся")
        tapWhenReady(myEvents, "«Мои события»")

        let card = app.staticTexts[title]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Созданное событие не появилось в списке")
        tapWhenReady(card, "карточка события")

        let edit = app.buttons["pencil"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "На карточке нет кнопки редактирования")
        tapWhenReady(edit, "кнопка редактирования")

        let deleteRow = app.buttons["Удалить событие"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10), "В редактировании нет кнопки удаления")
        // Кнопка удаления в самом низу формы редактирования — может быть за
        // границей экрана, тогда до неё надо докрутить.
        tapWhenReady(deleteRow, "«Удалить событие»", scrollIn: app.scrollViews.firstMatch)
        tapWhenReady(app.buttons["Удалить"], "подтверждение удаления")

        // Удаление обязано быть видимым: карточка закрывается сама, а события
        // больше нет в списке. Раньше не происходило ни того, ни другого.
        XCTAssertTrue(app.navigationBars["Мои события"].waitForExistence(timeout: 10),
                      "После удаления карточка события осталась открытой")
        XCTAssertFalse(card.waitForExistence(timeout: 5),
                       "Удалённое событие всё ещё в списке «Мои события»")
    }
}
