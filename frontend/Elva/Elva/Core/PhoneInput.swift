import Foundation

/// Приведение любого ввода телефона к формату сервера: «+7» и десять цифр.
///
/// Поле входа предзаполнено «+7», и вставленный из буфера номер приклеивался
/// к нему: получалось «+7+79991694822». Вход не проходил, и со стороны это
/// выглядело как «вставка не работает». Сюда же — привычные людям варианты:
/// «8 999...», номер без кода страны, скобки и дефисы из «Контактов».
enum PhoneInput {
    static func normalize(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)

        if digits.count == 12, digits.hasPrefix("77") {
            digits.removeFirst()                       // «+7» поля + вставленный «+7…»
        }
        if digits.count == 11, digits.hasPrefix("8") {
            digits = "7" + digits.dropFirst()          // привычное «8 999 …»
        }
        if digits.count == 10, digits.hasPrefix("9") {
            digits = "7" + digits                      // номер без кода страны
        }
        if digits.count > 11 {
            digits = "7" + digits.suffix(10)           // прочие дубли после вставки
        }
        return digits.isEmpty ? "+7" : "+" + digits
    }
}
