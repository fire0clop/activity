import Foundation

/// Парсинг/форматирование дат из строк бэка. Форматтеры кешируются (дорого создавать).
enum DateFormat {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static func ru(_ fmt: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = fmt; return f
    }
    private static let fPrettyDay = ru("EE, d MMMM")
    private static let fDateTime = ru("d MMMM, HH:mm")
    private static let fMemberSince = ru("d MMMM yyyy")
    private static let fTime = ru("HH:mm")
    private static let fDayNum = ru("d")
    private static let fMonthShort = ru("MMM")
    private static let fWeekday = ru("EE")

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoNoFrac.date(from: s)
    }

    static func dayDate(_ s: String) -> Date? { dayParser.date(from: s) }

    /// "2026-06-21" → "Сб, 21 июня".
    static func prettyDay(_ s: String) -> String {
        guard let d = dayDate(s) else { return s }
        return fPrettyDay.string(from: d)
    }

    /// "2026-06-21" → ("21", "ИЮН", "СБ") для дата-пилюли в карточке.
    static func dayPill(_ s: String) -> (num: String, month: String, weekday: String) {
        guard let d = dayDate(s) else { return (s, "", "") }
        return (fDayNum.string(from: d), fMonthShort.string(from: d).uppercased(),
                fWeekday.string(from: d).uppercased())
    }

    static func prettyDateTime(_ s: String?) -> String {
        guard let d = parse(s) else { return "—" }
        return fDateTime.string(from: d)
    }

    /// Дата без времени: "8 июля 2026" — для «в приложении с …» (не машинный лог с минутами).
    static func memberSince(_ s: String?) -> String {
        guard let d = parse(s) else { return "—" }
        return fMemberSince.string(from: d)
    }

    static func time(_ s: String?) -> String {
        guard let d = parse(s) else { return "" }
        return fTime.string(from: d)
    }
}
