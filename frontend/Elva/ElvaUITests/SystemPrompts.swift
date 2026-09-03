import XCTest

extension XCTestCase {
    /// Ждёт, пока приложение отрисует интерфейс после запуска.
    ///
    /// Ждём появления панели вкладок, а не её доступности: во время обучения она
    /// нарочно перекрыта подсветкой, и ожидание нажимаемости зависало бы ровно
    /// в тех тестах, которые обучение и проверяют.
    /// Тесты ходят на боевой сервер, и при обрыве сети приложение честно висит
    /// на спиннере входа. Ждём с запасом, а если не дождались — падаем с одной
    /// понятной причиной, а не каскадом «кнопки нет» по всему тесту.
    func settleAfterLaunch(_ app: XCUIApplication, timeout: TimeInterval = 60,
                           file: StaticString = #filePath, line: UInt = #line) {
        if !app.buttons["Лента"].waitForExistence(timeout: timeout) {
            XCTFail("Приложение не загрузилось за \(Int(timeout)) с — похоже на обрыв сети до сервера",
                    file: file, line: line)
        }
    }

    /// Ждёт, пока элемент станет доступен для нажатия.
    ///
    /// Опрашиваем только само приложение. Раньше здесь на каждой итерации ещё и
    /// снимался слой системных диалогов — десятки тяжёлых снимков дерева за один
    /// вызов, после которых прогон начинал видеть пустой экран там, где всё было
    /// нарисовано. Диалогов в тестах нет: запросы геопозиции и уведомлений
    /// отключены флагами UITEST_SKIP_LOCATION и UITEST_SKIP_PUSH.
    @discardableResult
    func waitForApp(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return element.exists && element.isHittable
    }

    /// Доводит приложение до состояния, когда панель вкладок доступна.
    ///
    /// Обучение появляется не в фиксированный момент: разово проверить «есть ли
    /// оно» и пойти дальше нельзя — оно всплывает следом и перекрывает вкладки,
    /// после чего тест падает на любом нажатии. Поэтому ждём именно доступности
    /// вкладок, закрывая подсветку всякий раз, когда она возникает.
    func clearTourIfShown(_ app: XCUIApplication, timeout: TimeInterval = 25) {
        let tabs = app.buttons["Профиль"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tabs.exists, tabs.isHittable { return }
            for id in ["tour.skip", "tour.next"] {
                let b = app.buttons[id]
                if b.exists, b.isHittable { b.tap(); break }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    /// Нажимает, дождавшись доступности, а на длинных экранах — докрутив до элемента.
    func tapWhenReady(_ element: XCUIElement, _ what: String,
                      scrollIn container: XCUIElement? = nil,
                      timeout: TimeInterval = 20, file: StaticString = #filePath,
                      line: UInt = #line) {
        if waitForApp(element, timeout: timeout) {
            element.tap()
            return
        }
        // Элемент есть, но не нажимается — на длинных экранах он просто ниже
        // границы. Подкручиваем и пробуем ещё раз.
        if element.exists, let container, container.exists {
            for _ in 0..<3 {
                container.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                if element.isHittable { element.tap(); return }
            }
        }
        XCTFail("Не дождались: \(what)", file: file, line: line)
    }
}
