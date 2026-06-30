import SwiftUI

/// Стартовый экран: вход по телефону и паролю (без SMS).
struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var phone = "+7"
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private var isValid: Bool { phone.count >= 11 && password.count >= 6 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 54)).foregroundStyle(Theme.accent)
                    Text("Сходка").font(.largeTitle).fontWeight(.bold)
                    Text("Найди компанию под любую активность")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    TextField("+79991234567", text: $phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                PrimaryButton(title: "Войти", isLoading: isLoading, isEnabled: isValid) {
                    Task { await login() }
                }

                HStack {
                    NavigationLink("Регистрация") { RegisterView() }
                    Spacer()
                    NavigationLink("Забыли пароль?") {
                        PasswordResetView(prefillPhone: phone == "+7" ? "" : phone)
                    }
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
        }
    }

    private func login() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            try await auth.login(phone: phone, password: password)
        } catch let err as APIError {
            errorText = err.message
        } catch { errorText = "Нет соединения с сервером" }
    }
}
