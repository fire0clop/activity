import XCTest

/// Съёмочный прогон для видео App Review: правила → вход → жалоба → блокировка.
/// Не проверка, а инструмент: паузы стоят, чтобы зритель успевал прочитать экран.
final class DemoVideoTests: XCTestCase {

    private var token: String { ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? "" }
    private var blockedID: String?

    func testRecordReviewScenario() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchEnvironment["UITEST_RESET_TOS"] = "1"
        app.launchEnvironment["UITEST_RESET_SESSION"] = "1"
        // Обучение в этом ролике не показываем: Apple ждёт правила, жалобу и
        // блокировку, а подсветка перекрывала бы нужные кнопки.
        app.launchArguments += ["-feed.scope", "nearMe",
                                "-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()

        addTeardownBlock { [token] in
            guard let id = self.blockedID else { return }
            var req = URLRequest(url: URL(string: "https://api.event-serv.ru/api/v1/users/\(id)/block")!)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }

        // ЧАСТЬ 1: правила до входа.
        let title = app.staticTexts["Правила сообщества"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Правила не показаны")
        pause(2.5)
        app.swipeUp(velocity: .slow)          // показать все пункты
        pause(2.0)
        tapWhenReady(app.buttons["terms.accept"], "«Принимаю правила»")
        pause(1.5)

        // ЧАСТЬ 2: вход демо-аккаунтом.
        let phone = app.textFields.firstMatch
        XCTAssertTrue(phone.waitForExistence(timeout: 10), "Экран входа не открылся")
        phone.tap()
        phone.typeText("9991694822")
        // Пароль — вставкой: на симуляторе русская раскладка, и латиница
        // через typeText не печатается (поле молча оставалось пустым).
        UIPasteboard.general.string = "ZhEwQjsjMeXCFw"
        let pass = app.secureTextFields.firstMatch
        pass.tap()
        pause(0.8)
        pass.press(forDuration: 1.2)
        let paste = app.menuItems["Вставить"].exists ? app.menuItems["Вставить"] : app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Меню вставки не показалось")
        paste.tap()
        pause(1.0)
        tapWhenReady(app.buttons["Войти"], "«Войти»")
        settleAfterLaunch(app)
        // Система предлагает сохранить пароль — вежливо отказываемся.
        for label in ["Не сейчас", "Not Now"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 5) { b.tap(); break }
        }
        pause(2.5)

        // ЧАСТЬ 3: жалоба на событие.
        guard let organizerName = fetchOrganizerName(ofEvent: "Настолки до последнего автобуса"),
              let organizerID = fetchOrganizerID(ofEvent: "Настолки до последнего автобуса") else {
            XCTFail("Не удалось узнать организатора"); return
        }
        blockedID = organizerID

        let card = app.staticTexts["Настолки до последнего автобуса"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Событие не видно")
        tapWhenReady(card, "карточка события")
        pause(2.0)
        tapWhenReady(app.buttons["Пожаловаться на событие"], "кнопка жалобы")
        pause(2.0)
        tapWhenReady(app.buttons["Неуместное содержание"], "причина жалобы")
        pause(2.0)

        // ЧАСТЬ 4: блокировка организатора.
        let organizer = app.staticTexts[organizerName]
        XCTAssertTrue(organizer.waitForExistence(timeout: 10), "Организатор не показан")
        tapWhenReady(organizer, "профиль организатора", scrollIn: app.scrollViews.firstMatch)
        pause(2.0)
        app.swipeUp(velocity: .slow)          // до кнопок внизу профиля
        pause(1.5)
        tapWhenReady(app.buttons["Заблокировать"], "«Заблокировать»",
                     scrollIn: app.scrollViews.firstMatch)
        pause(1.5)
        tapWhenReady(app.buttons["Заблокировать"].firstMatch, "подтверждение")
        XCTAssertTrue(app.staticTexts["Пользователь заблокирован."].waitForExistence(timeout: 10))
        pause(2.5)

        // ЧАСТЬ 5: назад — контент заблокированного исчез из ленты мгновенно.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable { back.tap() }
        let feedMark = app.staticTexts["Чем займёмся?"]
        XCTAssertTrue(feedMark.waitForExistence(timeout: 8), "Не вернулись в ленту")
        XCTAssertFalse(card.exists, "События заблокированного остались")
        pause(4.0)                             // финальный кадр: лента без его событий
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func fetchOrganizerName(ofEvent title: String) -> String? {
        fetchOrganizerField(ofEvent: title, field: "name")
    }
    private func fetchOrganizerID(ofEvent title: String) -> String? {
        fetchOrganizerField(ofEvent: title, field: "id")
    }
    private func fetchOrganizerField(ofEvent title: String, field: String) -> String? {
        var req = URLRequest(url: URL(string:
            "https://api.event-serv.ru/api/v1/events?lat=55.751&lng=37.618&radius_km=25")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var result: String?
        let done = expectation(description: "организатор найден")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { done.fulfill() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }
            for item in items where item["title"] as? String == title {
                if let org = item["organizer"] as? [String: Any] { result = org[field] as? String }
                return
            }
        }.resume()
        wait(for: [done], timeout: 20)
        return result
    }
}
