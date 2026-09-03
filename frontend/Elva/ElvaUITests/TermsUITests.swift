import XCTest

/// Согласие с правилами до входа — требование App Store 1.2 для приложений
/// с пользовательским контентом. Ревьюер проверяет ровно этот путь.
final class TermsUITests: XCTestCase {

    private func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()
        // Без токенов: нужен именно путь нового человека. Отметку о согласии
        // сбрасываем аргументом, чтобы тест не зависел от прежних запусков.
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchEnvironment["UITEST_RESET_TOS"] = "1"
        app.launchEnvironment["UITEST_RESET_SESSION"] = "1"
        app.launch()
        return app
    }

    func testTermsShownBeforeLoginAndGateWorks() {
        let app = launchSignedOut()

        let title = app.staticTexts["Правила сообщества"]
        XCTAssertTrue(title.waitForExistence(timeout: 15),
                      "Правила не показаны перед входом")
        XCTAssertTrue(app.staticTexts["Нулевая терпимость"].exists,
                      "В правилах нет пункта о нулевой терпимости")

        // Пока согласия нет — входа и регистрации не существует.
        XCTAssertFalse(app.buttons["Войти"].exists,
                       "Вход доступен до согласия с правилами")

        tapWhenReady(app.buttons["terms.accept"], "«Принимаю правила»")
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 10),
                      "После согласия не открылся экран входа")
    }

    func testAcceptanceSurvivesRelaunch() {
        let app = launchSignedOut()
        tapWhenReady(app.buttons["terms.accept"], "«Принимаю правила»")
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 10))

        // Повторный запуск без сброса отметки: правила не должны требоваться заново.
        let again = XCUIApplication()
        again.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        again.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        again.launchEnvironment["UITEST_RESET_SESSION"] = "1"
        again.launch()
        XCTAssertTrue(again.buttons["Войти"].waitForExistence(timeout: 10),
                      "Согласие не пережило перезапуск")
        XCTAssertFalse(again.staticTexts["Правила сообщества"].exists,
                       "Правила требуют согласия повторно")
    }
}
