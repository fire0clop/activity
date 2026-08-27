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
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        XCTAssertEqual(status, 201, "Не удалось подготовить событие — проверьте токен")
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = token
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] =
            ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchArguments += ["-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()
        return app
    }

    func testDeletedEventDisappearsFromMyEvents() throws {
        try createEvent()
        let app = launchApp()

        app.buttons["Профиль"].tap()
        let myEvents = app.staticTexts["Мои события"]
        XCTAssertTrue(myEvents.waitForExistence(timeout: 10), "Профиль не открылся")
        myEvents.tap()

        let card = app.staticTexts[title]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Созданное событие не появилось в списке")
        card.tap()

        let edit = app.buttons["pencil"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "На карточке нет кнопки редактирования")
        edit.tap()

        let deleteRow = app.buttons["Удалить событие"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10), "В редактировании нет кнопки удаления")
        deleteRow.tap()
        app.buttons["Удалить"].tap()

        // Удаление обязано быть видимым: карточка закрывается сама, а события
        // больше нет в списке. Раньше не происходило ни того, ни другого.
        XCTAssertTrue(app.navigationBars["Мои события"].waitForExistence(timeout: 10),
                      "После удаления карточка события осталась открытой")
        XCTAssertFalse(card.waitForExistence(timeout: 5),
                       "Удалённое событие всё ещё в списке «Мои события»")
    }
}
