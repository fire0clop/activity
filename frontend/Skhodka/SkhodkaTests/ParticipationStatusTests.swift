import Testing
@testable import Skhodka

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
