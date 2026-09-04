import XCTest

/// Вставка учётных данных на экране входа.
///
/// Поле телефона предзаполнено «+7», и вставленный номер приклеивался к нему:
/// «+7+79991694822». Вход не проходил, а со стороны это выглядело как
/// «вставка не работает» — на это жаловались и при подготовке видео для
/// App Review. Проверяем итоговое значение поля, а не сам факт вставки.
final class PasteUITests: XCTestCase {
    func testPastedPhoneAndPasswordLandCorrectly() {
        UIPasteboard.general.string = "+79991694822"

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SKIP_LOCATION"] = "1"
        app.launchEnvironment["UITEST_SKIP_PUSH"] = "1"
        app.launchEnvironment["UITEST_RESET_SESSION"] = "1"
        app.launchArguments += ["-tos.accepted.version", "1.0"]
        app.launch()

        let phone = app.textFields.firstMatch
        XCTAssertTrue(phone.waitForExistence(timeout: 20), "Поле телефона не появилось")
        phone.tap()
        phone.press(forDuration: 1.2)
        let paste = app.menuItems["Вставить"].exists ? app.menuItems["Вставить"] : app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Меню вставки не показалось")
        paste.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(phone.value as? String, "+79991694822",
                       "Вставленный номер должен заменить префикс, а не приклеиться к нему")

        UIPasteboard.general.string = "ZhEwQjsjMeXCFw"
        let pass = app.secureTextFields.firstMatch
        pass.tap()
        pass.press(forDuration: 1.2)
        let paste2 = app.menuItems["Вставить"].exists ? app.menuItems["Вставить"] : app.menuItems["Paste"]
        XCTAssertTrue(paste2.waitForExistence(timeout: 5), "Меню вставки в пароль не показалось")
        paste2.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual((pass.value as? String)?.count, 14, "Пароль вставился не целиком")
    }
}
