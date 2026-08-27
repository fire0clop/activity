import XCTest

/// Действия в профиле: они не покрывались ничем, и «ничего не происходит»
/// обнаруживалось только руками.
final class ProfileUITests: XCTestCase {

    private func openProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        // Обучение не должно перекрывать экран во время проверки профиля.
        app.launchArguments += ["-tour.feed.v1", "YES", "-tour.event.v1", "YES"]
        app.launch()

        let profileTab = app.buttons["Профиль"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 15), "Вкладка «Профиль» не появилась")
        profileTab.tap()
        return app
    }

    /// Пока обучение не пройдено, оно висит поверх всего приложения. Проверяем,
    /// что оно не блокирует другие вкладки.
    func testProfileWorksWhileTourNotSeen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchArguments += ["-tour.feed.v1", "NO"]   // обучение НЕ пройдено
        app.launch()

        XCTAssertTrue(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 15),
                      "Обучение не появилось")

        // Первый тап мимо пояснения закрывает обучение — из него всегда есть выход.
        let profileTab = app.buttons["Профиль"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertFalse(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 2),
                       "Тап мимо пояснения не закрыл обучение — человек заперт в нём")

        // Второй открывает вкладку: приложение снова управляемо.
        profileTab.tap()
        let row = app.buttons["Как это работает"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Профиль не открылся")
        XCTAssertTrue(row.isHittable,
                      "Кнопка в профиле недоступна — поверх неё лежит слой обучения")
    }

    func testHowItWorksShowsConfirmation() throws {
        let app = openProfile()
        let row = app.buttons["Как это работает"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Строки «Как это работает» нет")
        XCTAssertTrue(row.isHittable, "Строка есть, но недоступна для нажатия")
        row.tap()
        XCTAssertTrue(app.staticTexts["Подсказки включены"].waitForExistence(timeout: 3),
                      "После нажатия ничего не произошло — подтверждение не показано")
    }

    func testChangePasswordOpensSheet() throws {
        let app = openProfile()
        let row = app.buttons["Сменить пароль"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Строки «Сменить пароль» нет")
        XCTAssertTrue(row.isHittable, "Строка есть, но недоступна для нажатия")
        row.tap()
        // Экран восстановления пароля начинается с ввода телефона.
        XCTAssertTrue(app.buttons["Получить код"].waitForExistence(timeout: 3),
                      "После нажатия ничего не произошло — окно смены пароля не открылось")
    }
}
