import Testing
@testable import Elva

@Suite("Ввод телефона")
struct PhoneInputTests {
    @Test("Вставка полного номера в поле с «+7» не удваивает код")
    func pasteIntoPrefilled() {
        #expect(PhoneInput.normalize("+7+79991694822") == "+79991694822")
    }

    @Test("Привычные людям варианты приводятся к формату сервера")
    func commonFormats() {
        #expect(PhoneInput.normalize("8 (999) 169-48-22") == "+79991694822")
        #expect(PhoneInput.normalize("9991694822") == "+79991694822")
        #expect(PhoneInput.normalize("+7 999 169 48 22") == "+79991694822")
        #expect(PhoneInput.normalize("+7+7 (999) 169-48-22") == "+79991694822")
    }

    @Test("Набор по одной цифре не искажается")
    func typingDigitByDigit() {
        var value = "+7"
        for ch in "9991694822" {
            value = PhoneInput.normalize(value + String(ch))
        }
        #expect(value == "+79991694822")
    }

    @Test("Пустое поле возвращается к «+7»")
    func emptyFallsBackToPrefix() {
        #expect(PhoneInput.normalize("") == "+7")
        #expect(PhoneInput.normalize("+") == "+7")
    }
}
