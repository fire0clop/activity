import SwiftUI

/// Регистрация: телефон → код из SMS → пароль.
struct RegisterView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var phone = "+7"
    @State private var code = ""
    @State private var password = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var resendIn = 0
    @State private var errorText: String?
    @FocusState private var codeFocused: Bool

    private var phoneValid: Bool { phone.count >= 11 }
    private var canRegister: Bool { code.count == 6 && password.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Регистрация").font(.title2).fontWeight(.bold).padding(.top)

                TextField("+79991234567", text: $phone)
                    .keyboardType(.phonePad).textContentType(.telephoneNumber)
                    .disabled(codeSent)
                    .padding().background(Theme.secondaryBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                if !codeSent {
                    PrimaryButton(title: "Получить код", isLoading: isLoading, isEnabled: phoneValid) {
                        Task { await sendCode() }
                    }
                } else {
                    // Код из SMS — обычная клавиатура, чтобы работала автоподстановка над клавиатурой.
                    TextField("Код из SMS", text: $code)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }

                    SecureField("Придумайте пароль (от 6 символов)", text: $password)
                        .textContentType(.newPassword)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                    Button(resendIn > 0 ? "Отправить код повторно (\(resendIn))" : "Отправить код повторно") {
                        Task { await sendCode() }
                    }
                    .font(.footnote).disabled(resendIn > 0)

                    PrimaryButton(title: "Зарегистрироваться", isLoading: isLoading, isEnabled: canRegister) {
                        Task { await register() }
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendCode() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await auth.requestCode(phone: phone)
            codeSent = true
            startResendTimer(resp.resendAfterSec)
            codeFocused = true
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Нет соединения с сервером" }
    }

    private func register() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            try await auth.register(phone: phone, code: code, password: password)
        } catch let err as APIError {
            errorText = err.message
            if err.isCode(.invalidCode) || err.isCode(.codeExpired) { code = "" }
        } catch { errorText = "Нет соединения с сервером" }
    }

    private func startResendTimer(_ seconds: Int) {
        resendIn = seconds
        Task {
            while resendIn > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                resendIn -= 1
            }
        }
    }
}
