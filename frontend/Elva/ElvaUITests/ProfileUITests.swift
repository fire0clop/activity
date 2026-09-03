import XCTest

/// Действия в профиле: они не покрывались ничем, и «ничего не происходит»
/// обнаруживалось только руками.
final class ProfileUITests: XCTestCase {

    private func openProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        // Обучение не должно перекрывать экран во время проверки профиля.
        app.launchArguments += ["-feed.scope", "nearMe",
                                "-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()
        settleAfterLaunch(app)

        let profileTab = app.buttons["Профиль"]
        XCTAssertTrue(waitForApp(profileTab), "Вкладка «Профиль» не появилась")
        tapWhenReady(profileTab, "вкладка «Профиль»")
        return app
    }

    /// Пока обучение не пройдено, оно висит поверх всего приложения. Проверяем,
    /// что оно не блокирует другие вкладки.
    func testProfileWorksWhileTourNotSeen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchArguments += ["-feed.scope", "nearMe",
                                "-tour.feed.v1", "NO"]   // обучение НЕ пройдено
        app.launch()
        settleAfterLaunch(app)

        XCTAssertTrue(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 15),
                      "Обучение не появилось")

        // Первый тап мимо пояснения закрывает обучение — из него всегда есть выход.
        let profileTab = app.buttons["Профиль"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        tapWhenReady(profileTab, "вкладка «Профиль»")
        XCTAssertFalse(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 2),
                       "Тап мимо пояснения не закрыл обучение — человек заперт в нём")

        // Второй открывает вкладку: приложение снова управляемо.
        tapWhenReady(profileTab, "вкладка «Профиль»")
        let row = app.buttons["Как это работает"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Профиль не открылся")
        XCTAssertTrue(row.isHittable,
                      "Кнопка в профиле недоступна — поверх неё лежит слой обучения")
    }

    func testHowItWorksShowsConfirmation() throws {
        let app = openProfile()
        let row = app.buttons["Как это работает"]
        tapWhenReady(row, "строка в профиле", scrollIn: app.scrollViews.firstMatch)
        XCTAssertTrue(app.staticTexts["Подсказки включены"].waitForExistence(timeout: 3),
                      "После нажатия ничего не произошло — подтверждение не показано")
    }

    func testChangePasswordOpensSheet() throws {
        let app = openProfile()
        let row = app.buttons["Сменить пароль"]
        tapWhenReady(row, "строка в профиле", scrollIn: app.scrollViews.firstMatch)
        // Экран восстановления пароля начинается с ввода телефона.
        XCTAssertTrue(app.buttons["Получить код"].waitForExistence(timeout: 3),
                      "После нажатия ничего не произошло — окно смены пароля не открылось")
    }

    /// «Как это работает» обязано доводить дело до конца.
    ///
    /// Сообщение о включении подсказок всплывало, а на ленте потом ничего не
    /// появлялось: сброс происходит на вкладке «Профиль», а обучение стартовало
    /// только если человек уже был на ленте в этот момент.
    ///
    /// Отметку «обучение пройдено» здесь нельзя подкладывать аргументом запуска:
    /// домен аргументов перекрывает запись самого приложения, и сброс изнутри
    /// оказался бы не виден. Поэтому проходим ровно тот путь, что и человек.
    func testHowItWorksActuallyShowsTourOnFeed() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] =
            ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] =
            ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchArguments += ["-feed.scope", "nearMe"]
        app.launch()
        settleAfterLaunch(app)

        // Приводим к известному состоянию: обучение пройдено и не мешает.
        let firstStep = app.staticTexts["Здесь три ленты"]
        clearTourIfShown(app)
        XCTAssertFalse(firstStep.exists, "Обучение не закрылось")

        tapWhenReady(app.buttons["Профиль"], "вкладка «Профиль»")
        let row = app.buttons["Как это работает"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Профиль не открылся")
        tapWhenReady(row, "строка в профиле", scrollIn: app.scrollViews.firstMatch)
        tapWhenReady(app.buttons["Хорошо"], "подтверждение")

        tapWhenReady(app.buttons["Лента"], "вкладка «Лента»")
        XCTAssertTrue(firstStep.waitForExistence(timeout: 10),
                      "Подсказки включили, но на ленте они не показались")
    }
}
