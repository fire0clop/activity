import Foundation
import Testing
@testable import Skhodka

/// Сетевые тесты сериализованы: MockURLProtocol.handler — общий для процесса.
@Suite("APIClient", .serialized)
struct APIClientTests {
    private let base = URL(string: "http://unit.test/api/v1")!

    private func makeClient(store: TokenStore = TokenStore()) -> APIClient {
        APIClient(base: base, tokenStore: store, session: MockURLProtocol.makeSession())
    }

    init() { MockURLProtocol.reset() }

    @Test("Добавляет Bearer-токен в авторизованный запрос")
    func addsBearerHeader() async throws {
        let store = TokenStore()
        store.save(access: "acc-1", refresh: "ref-1")
        defer { store.clear() }
        MockURLProtocol.handler = { _ in (200, #"{"ok": true}"#) }

        struct Ok: Decodable { let ok: Bool }
        let _: Ok = try await makeClient(store: store).send(Endpoint(path: "/ping"))

        let auth = MockURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer acc-1")
    }

    @Test("401 -> refresh -> повтор запроса с новым токеном")
    func refreshesOn401() async throws {
        let store = TokenStore()
        store.save(access: "old", refresh: "ref-1")
        defer { store.clear() }

        MockURLProtocol.handler = { req in
            let path = req.url!.path
            if path.hasSuffix("/auth/refresh") {
                return (200, #"{"access_token":"new","refresh_token":"ref-2","token_type":"bearer","expires_in":1800}"#)
            }
            let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth == "Bearer old" {
                return (401, #"{"error":{"code":"unauthorized","message":"истёк"}}"#)
            }
            return (200, #"{"ok": true}"#)
        }

        struct Ok: Decodable { let ok: Bool }
        let ok: Ok = try await makeClient(store: store).send(Endpoint(path: "/users/me"))
        #expect(ok.ok)
        #expect(store.accessToken == "new")
        #expect(store.refreshToken == "ref-2")
    }

    @Test("Неудачный refresh -> onUnauthorized")
    func signsOutWhenRefreshFails() async {
        let store = TokenStore()
        store.save(access: "old", refresh: "dead")
        defer { store.clear() }
        MockURLProtocol.handler = { req in
            req.url!.path.hasSuffix("/auth/refresh")
                ? (401, #"{"error":{"code":"unauthorized","message":"нет"}}"#)
                : (401, #"{"error":{"code":"unauthorized","message":"истёк"}}"#)
        }

        let client = makeClient(store: store)
        var unauthorized = false
        client.onUnauthorized = { unauthorized = true }

        struct Ok: Decodable { let ok: Bool }
        await #expect(throws: APIError.self) {
            let _: Ok = try await client.send(Endpoint(path: "/users/me"))
        }
        #expect(unauthorized)
    }

    @Test("403 profile_incomplete -> onProfileIncomplete + ошибка наружу")
    func interceptsProfileIncomplete() async {
        let store = TokenStore()
        store.save(access: "acc", refresh: "ref")
        defer { store.clear() }
        MockURLProtocol.handler = { _ in
            (403, #"{"error":{"code":"profile_incomplete","message":"Заполните профиль"}}"#)
        }

        let client = makeClient(store: store)
        var intercepted = false
        client.onProfileIncomplete = { intercepted = true }

        struct Ok: Decodable { let ok: Bool }
        await #expect(throws: APIError.self) {
            let _: Ok = try await client.send(Endpoint(path: "/events", method: .post))
        }
        #expect(intercepted)
    }

    @Test("Серверная ошибка декодируется в APIError с типизированным кодом")
    func decodesAPIError() async {
        let store = TokenStore()
        store.save(access: "acc", refresh: "ref")
        defer { store.clear() }
        MockURLProtocol.handler = { _ in
            (409, #"{"error":{"code":"already_joined","message":"Вы уже в событии"}}"#)
        }

        struct Ok: Decodable { let ok: Bool }
        do {
            let _: Ok = try await makeClient(store: store).send(Endpoint(path: "/events/1/join", method: .post))
            Issue.record("ожидали ошибку")
        } catch let err as APIError {
            #expect(err.isCode(.alreadyJoined))
            #expect(err.status == 409)
            #expect(err.message == "Вы уже в событии")
        } catch {
            Issue.record("не тот тип ошибки: \(error)")
        }
    }

    @Test("Параллельные 401 -> один общий refresh (без повторной ротации токена)")
    func dedupesConcurrentRefresh() async throws {
        let store = TokenStore()
        store.save(access: "old", refresh: "ref-1")
        defer { store.clear() }

        let refreshHits = LockedCounter()
        MockURLProtocol.handler = { req in
            let path = req.url!.path
            if path.hasSuffix("/auth/refresh") {
                refreshHits.increment()
                return (200, #"{"access_token":"new","refresh_token":"ref-2","token_type":"bearer","expires_in":1800}"#)
            }
            let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
            return auth == "Bearer old"
                ? (401, #"{"error":{"code":"unauthorized","message":"истёк"}}"#)
                : (200, #"{"ok": true}"#)
        }

        struct Ok: Decodable { let ok: Bool }
        let client = makeClient(store: store)
        // Два авторизованных запроса стартуют одновременно и оба ловят 401.
        async let a: Ok = client.send(Endpoint(path: "/users/me"))
        async let b: Ok = client.send(Endpoint(path: "/conversations"))
        _ = try await (a, b)

        // Без дедупликации было бы два refresh — второй ротировал бы уже невалидный токен.
        #expect(refreshHits.count == 1)
        #expect(store.refreshToken == "ref-2")
    }
}

/// Потокобезопасный счётчик для подсчёта обращений из sync-обработчика MockURLProtocol.
final class LockedCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
