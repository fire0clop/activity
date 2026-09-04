import XCTest

/// Блокировка глазами ревьюера App Store (1.2): контент заблокированного
/// должен исчезнуть из ленты мгновенно, без ручного обновления.
///
/// Ровно этот путь снимается на видео для проверки — и ровно на нём всплыла
/// жалоба «события не исчезли»: сервер фильтровал верно, а лента продолжала
/// показывать кэш.
final class BlockUITests: XCTestCase {

    private var token: String { ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? "" }
    private var blockedID: String?

    func testBlockedOrganizerVanishesInstantly() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = token
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchArguments += ["-feed.scope", "nearMe",
                                "-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()
        settleAfterLaunch(app)

        // Разблокируем в конце при любом исходе: иначе повторный прогон (и
        // ревьюер после нас) не увидит событий Лены.
        addTeardownBlock { [token] in
            guard let id = self.blockedID else { return }
            var req = URLRequest(url: URL(string: "https://api.event-serv.ru/api/v1/users/\(id)/block")!)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }

        // Имя организатора не зашиваем: при пересеве витрины оно меняется.
        // Id забираем до блокировки: после неё лента этого организатора уже
        // не отдаёт, и уборка в teardown осталась бы ни с чем.
        guard let organizerName = fetchOrganizerName(ofEvent: "Настолки до последнего автобуса"),
              let organizerID = fetchOrganizerID(ofEvent: "Настолки до последнего автобуса") else {
            XCTFail("Не удалось узнать организатора события через API"); return
        }
        blockedID = organizerID

        let card = app.staticTexts["Настолки до последнего автобуса"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Событие не видно в ленте")
        tapWhenReady(card, "карточка события")

        let organizer = app.staticTexts[organizerName]
        XCTAssertTrue(organizer.waitForExistence(timeout: 15), "Организатор не показан")
        // Строка организатора ниже первого экрана карточки — докручиваем.
        tapWhenReady(organizer, "профиль организатора", scrollIn: app.scrollViews.firstMatch)

        let block = app.buttons["Заблокировать"]
        tapWhenReady(block, "«Заблокировать»", scrollIn: app.scrollViews.firstMatch)
        // Появляется диалог «Заблокировать пользователя?» — подтверждаем.
        tapWhenReady(app.buttons["Заблокировать"].firstMatch, "подтверждение блокировки")
        // Дадим запросу дойти; id для уборки достанем из подтверждения на экране.
        XCTAssertTrue(app.staticTexts["Пользователь заблокирован."].waitForExistence(timeout: 10),
                      "Блокировка не подтвердилась")

        // Выходим из профиля; карточка события заблокированного закрывается
        // сама, и мы оказываемся сразу в ленте.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable { back.tap() }
        let feedMark = app.staticTexts["Чем займёмся?"]
        XCTAssertTrue(feedMark.waitForExistence(timeout: 8),
                      "Не вернулись в ленту после блокировки")
        XCTAssertFalse(card.waitForExistence(timeout: 6),
                       "События заблокированного остались в ленте")
        // У того же организатора в витрине есть и «Волейбол на площадке» —
        // проверяем, что исчезло всё его, а не только открытая карточка.
        XCTAssertFalse(app.staticTexts["Волейбол на площадке"].exists,
                       "Второе событие заблокированного осталось в ленте")
    }

    private func fetchOrganizerName(ofEvent title: String) -> String? {
        fetchOrganizerField(ofEvent: title, field: "name")
    }

    private func fetchOrganizerID(ofEvent title: String) -> String? {
        fetchOrganizerField(ofEvent: title, field: "id")
    }

    /// Организатор события — из того же API, что видит приложение.
    private func fetchOrganizerField(ofEvent title: String, field: String) -> String? {
        var req = URLRequest(url: URL(string:
            "https://api.event-serv.ru/api/v1/events?lat=55.751&lng=37.618&radius_km=25")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var result: String?
        let done = expectation(description: "id найден")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { done.fulfill() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }
            for item in items where item["title"] as? String == title {
                if let org = item["organizer"] as? [String: Any] {
                    result = org[field] as? String
                }
                return
            }
        }.resume()
        wait(for: [done], timeout: 20)
        return result
    }
}
