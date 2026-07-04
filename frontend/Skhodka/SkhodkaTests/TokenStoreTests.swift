import Testing
@testable import Skhodka

@Suite("TokenStore", .serialized)
struct TokenStoreTests {
    @Test("Сохраняет, читает из нового экземпляра и чистит")
    func saveReadClear() {
        let store = TokenStore()
        store.save(access: "a-token", refresh: "r-token")
        #expect(store.hasSession)

        // Новый экземпляр читает из Keychain
        let reloaded = TokenStore()
        #expect(reloaded.accessToken == "a-token")
        #expect(reloaded.refreshToken == "r-token")

        reloaded.clear()
        #expect(!reloaded.hasSession)
        #expect(TokenStore().accessToken == nil)
    }

    @Test("Повторный save перезаписывает значения")
    func overwrite() {
        let store = TokenStore()
        store.save(access: "first", refresh: "r1")
        store.save(access: "second", refresh: "r2")
        defer { store.clear() }
        #expect(TokenStore().accessToken == "second")
        #expect(TokenStore().refreshToken == "r2")
    }
}
