import Foundation
import SwiftUI

/// Единый источник состояния сессии + доступ к API. Внедряется через @EnvironmentObject.
@MainActor
final class AuthManager: ObservableObject {
    enum State {
        case loading        // проверяем сохранённую сессию
        case signedOut      // нужен вход
        case onboarding     // вошёл, но профиль не заполнен (фото+имя+«о себе»)
        case signedIn       // полный доступ
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var me: UserPrivate?

    let tokenStore: TokenStore
    let api: APIClient

    init() {
        let store = TokenStore()
        self.tokenStore = store
        self.api = APIClient(tokenStore: store)
        api.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.signOut() }
        }
        // Бэк ответил 403 profile_incomplete — принудительно возвращаем в онбординг.
        api.onProfileIncomplete = { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .signedIn else { return }
                self.state = .onboarding
            }
        }
        // Когда APNs выдаст токен — регистрируем устройство на бэке.
        PushCenter.shared.onToken = { [weak self] token in
            Task { @MainActor in await self?.registerDevice(token) }
        }
    }

    private func registerDevice(_ token: String) async {
        try? await api.sendVoid(Endpoint(
            path: "/devices", method: .post, body: DeviceBody(token: token, platform: "ios")))
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard tokenStore.hasSession else { state = .signedOut; return }
        await refreshMe()
    }

    func refreshMe() async {
        do {
            let me: UserPrivate = try await api.send(Endpoint(path: "/users/me"))
            self.me = me
            state = me.profileCompleted ? .signedIn : .onboarding
            if state == .signedIn {
                // Запрашиваем разрешение на пуши и регистрируем устройство.
                if let token = PushCenter.shared.apnsToken {
                    await registerDevice(token)
                } else {
                    PushCenter.shared.requestAuthorizationAndRegister()
                }
            }
        } catch let err as APIError where err.isCode(.unauthorized) {
            signOut()
        } catch {
            // сеть недоступна — оставляем гостем, чтобы дать возможность войти заново
            state = .signedOut
        }
    }

    // MARK: - Auth flow

    func requestCode(phone: String) async throws -> RequestCodeResponse {
        try await api.send(Endpoint(
            path: "/auth/request-code", method: .post,
            body: PhoneBody(phone: phone), requiresAuth: false
        ))
    }

    private func applyTokens(_ pair: TokenPair) async {
        tokenStore.save(access: pair.accessToken, refresh: pair.refreshToken)
        await refreshMe()
    }

    /// Регистрация: телефон + код из SMS + пароль.
    func register(phone: String, code: String, password: String) async throws {
        let pair: TokenPair = try await api.send(Endpoint(
            path: "/auth/register", method: .post,
            body: RegisterBody(phone: phone, code: code, password: password), requiresAuth: false))
        await applyTokens(pair)
    }

    /// Вход по паролю (без SMS).
    func login(phone: String, password: String) async throws {
        let pair: TokenPair = try await api.send(Endpoint(
            path: "/auth/login", method: .post,
            body: LoginBody(phone: phone, password: password), requiresAuth: false))
        await applyTokens(pair)
    }

    /// Смена/сброс пароля с подтверждением по SMS.
    func resetPassword(phone: String, code: String, newPassword: String) async throws {
        let pair: TokenPair = try await api.send(Endpoint(
            path: "/auth/reset-password", method: .post,
            body: ResetPasswordBody(phone: phone, code: code, new_password: newPassword),
            requiresAuth: false))
        await applyTokens(pair)
    }

    func signOut() {
        if let refresh = tokenStore.refreshToken {
            Task {
                try? await api.sendVoid(Endpoint(
                    path: "/auth/logout", method: .post,
                    body: RefreshBody(refresh_token: refresh), requiresAuth: false
                ))
            }
        }
        tokenStore.clear()
        me = nil
        state = .signedOut
    }
}
