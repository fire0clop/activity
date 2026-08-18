import Foundation
import Testing
@testable import Elva

@Suite("ParticipationStatus")
struct ParticipationStatusTests {
    @Test("Известные статусы разбираются в типизированные кейсы")
    func known() {
        #expect(ParticipationStatus(raw: "accepted") == .accepted)
        #expect(ParticipationStatus(raw: "pending") == .pending)
        #expect(ParticipationStatus(raw: "waitlisted") == .waitlisted)
        #expect(ParticipationStatus(raw: "rejected") == .rejected)
        #expect(ParticipationStatus(raw: "cancelled") == .cancelled)
    }

    @Test("Неизвестный статус и nil дают .unknown (не роняют декодирование)")
    func unknownAndNil() {
        #expect(ParticipationStatus(raw: "banned") == .unknown)
        #expect(ParticipationStatus(raw: nil) == .unknown)
        #expect(ParticipationStatus(raw: "") == .unknown)
    }
}

@Suite("Репутация в моделях")
struct ReputationDecodingTests {
    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("Новичок приходит без рейтинга — не с нулём")
    func newcomerHasNoRating() throws {
        let u = try decode("""
        {"id":"u1","name":"Аня","bio":null,"avatar_url":null,"photo_urls":[],
         "gender":"unspecified","age":null,"rating_avg":null,"rating_count":0,
         "events_created":0,"events_attended":0,"no_show_count":0,
         "member_since":"2026-08-01T10:00:00Z"}
        """, as: UserPublic.self)

        #expect(u.ratingAvg == nil)
        #expect(u.ratingCount == 0)
        #expect(u.isNewcomer)
        #expect(u.noShows == 0)
    }

    @Test("С отзывами рейтинг читается, неявки считаются")
    func ratedUser() throws {
        let u = try decode("""
        {"id":"u2","name":"Борис","bio":"люблю теннис","avatar_url":null,"photo_urls":[],
         "gender":"male","age":30,"rating_avg":4.5,"rating_count":2,
         "events_created":1,"events_attended":3,"no_show_count":1,
         "member_since":"2026-08-01T10:00:00Z"}
        """, as: UserPublic.self)

        #expect(u.ratingAvg == 4.5)
        #expect(u.noShows == 1)
        #expect(!u.isNewcomer)
    }

    @Test("Ответ без новых полей не роняет декодирование")
    func toleratesOlderPayload() throws {
        let o = try decode("""
        {"id":"o1","name":"Орг","avatar_url":null,"rating_avg":null}
        """, as: OrganizerBrief.self)

        #expect(o.ratingAvg == nil)
        #expect(o.reviewsCount == 0)
    }

    @Test("Отзыв о неявке приходит без оценки")
    func noShowReview() throws {
        let r = try decode("""
        {"id":"r1","event_id":"e1","target_id":"u1","rating":null,"comment":"не пришёл",
         "attended":false,"created_at":"2026-08-10T10:00:00Z",
         "author":{"id":"u9","name":"Орг","bio":null,"avatar_url":null,"photo_urls":[],
                   "gender":"unspecified","age":null,"rating_avg":null,"rating_count":0,
                   "events_created":0,"events_attended":0,"no_show_count":0,
                   "member_since":"2026-08-01T10:00:00Z"}}
        """, as: Review.self)

        #expect(r.rating == nil)
        #expect(r.didAttend == false)
    }
}

@Suite("Деньги")
struct PricingTests {
    @Test("Бесплатное событие не показывает сумм")
    func free() {
        let d = Pricing.detail(price: nil, split: "free", current: 3, max: 6)
        #expect(d.value == "Free")
        #expect(Pricing.short(price: nil, split: "free", current: 3) == "бесплатно")
    }

    @Test("С каждого: сумма не зависит от числа людей")
    func perPerson() {
        // Гидроциклы: каждый берёт свой, общего счёта нет.
        let a = Pricing.detail(price: 3000, split: "per_person", current: 2, max: 6)
        let b = Pricing.detail(price: 3000, split: "per_person", current: 5, max: 6)
        #expect(a.value == b.value)
        #expect(a.caption == "с человека")
        #expect(a.value.contains("3 000"))
    }

    @Test("Общий счёт делится на пришедших и дешевеет с набором")
    func sharedSplit() {
        // Выкуп ресторана на 100 000: сейчас идут четверо.
        let now = Pricing.detail(price: 100_000, split: "shared", current: 4, max: 10)
        #expect(now.value.contains("25 000"))
        #expect(now.caption.contains("10 000"))   // при полном составе

        // По мере набора доля падает.
        #expect(Pricing.perHead(price: 100_000, current: 8) == 12_500)
    }

    @Test("Пустой состав не приводит к делению на ноль")
    func noParticipantsYet() {
        #expect(Pricing.perHead(price: 5000, current: 0) == 5000)
    }

    @Test("В ленте видно долю, а не всю сумму выкупа")
    func feedShowsShare() {
        let shown = Pricing.short(price: 100_000, split: "shared", current: 5)
        #expect(shown.contains("20 000"))
        #expect(!shown.contains("100 000"))
    }
}
