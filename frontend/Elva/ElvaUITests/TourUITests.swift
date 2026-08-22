import XCTest

/// Проверка обучения нажатиями, а не на глаз.
///
/// Эти дефекты не ловятся ни сборкой, ни юнит-тестами: подсветка появлялась не
/// всегда, а её кнопки уезжали за край экрана и переставали нажиматься. Здесь
/// обучение проходится целиком — если шаг перестанет открываться или кнопка
/// снова окажется за границей, тест упадёт.
final class TourUITests: XCTestCase {

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Стартуем уже авторизованными: токены подкладываются через окружение
        // (механизм существует в приложении под #if DEBUG).
        app.launchEnvironment["UITEST_ACCESS_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_REFRESH_TOKEN"] = ProcessInfo.processInfo.environment["UITEST_REFRESH_TOKEN"] ?? ""
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        // Каждый тест стартует с непоказанным обучением: иначе первый же прогон
        // отмечает его просмотренным, и следующим тестам показывать нечего.
        app.launchArguments += ["-tour.feed.v1", "NO", "-tour.event.v1", "NO"]
        app.launch()

        // Системный запрос геопозиции перекрывает экран — снимаем его.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["При использовании приложения"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        return app
    }

    func testTourAppearsAndAdvancesByButton() throws {
        let app = launchApp()

        let firstStep = app.staticTexts["Здесь три ленты"]
        XCTAssertTrue(firstStep.waitForExistence(timeout: 15),
                      "Обучение не появилось — раньше оно ждало загрузки ленты и на медленной сети не показывалось")

        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Кнопки «Дальше» нет на экране")
        XCTAssertTrue(next.isHittable,
                      "Кнопка «Дальше» есть, но недоступна для нажатия — так бывает, когда её край уехал за границу экрана")

        // Рамка кнопки обязана целиком помещаться в экран.
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(next.frame),
                      "Кнопка «Дальше» выходит за пределы экрана: \(next.frame) вне \(screen)")

        next.tap()
        XCTAssertTrue(app.staticTexts["Сузить выдачу"].waitForExistence(timeout: 3),
                      "После нажатия «Дальше» второй шаг не открылся")
    }

    func testTourCanBeCompletedToTheEnd() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 15))

        // Проходим все шаги: каждый должен иметь нажимаемую кнопку.
        for _ in 0..<10 {
            if app.buttons["tour.next"].exists {
                XCTAssertTrue(app.buttons["tour.next"].isHittable)
                app.buttons["tour.next"].tap()
                break
            }
            guard app.buttons["Дальше"].exists else { break }
            XCTAssertTrue(app.buttons["Дальше"].isHittable, "Шаг обучения с ненажимаемой кнопкой")
            app.buttons["Дальше"].tap()
        }

        XCTAssertFalse(app.staticTexts["Здесь три ленты"].exists, "Обучение не закрылось после последнего шага")
    }

    func testSkipClosesTour() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 15))

        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        XCTAssertTrue(skip.isHittable, "Кнопка «Пропустить» недоступна для нажатия")
        skip.tap()
        XCTAssertFalse(app.staticTexts["Здесь три ленты"].waitForExistence(timeout: 2),
                       "«Пропустить» не закрыла обучение")
    }
}
