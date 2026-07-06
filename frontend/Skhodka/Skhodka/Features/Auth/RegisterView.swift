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
    @State private var acceptedTerms = false
    @FocusState private var codeFocused: Bool

    private var phoneValid: Bool { phone.count >= 11 }
    private var canRegister: Bool { code.count == 6 && password.count >= 6 && acceptedTerms }

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

                    consentRow

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

    /// Явное согласие с правилами и политикой (App Store Guideline 1.2 для UGC).
    private var consentRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { acceptedTerms.toggle() } label: {
                Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(acceptedTerms ? Theme.accent : Theme.ink2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Регистрируясь, я принимаю:").font(.footnote).foregroundStyle(Theme.ink2)
                HStack(spacing: 12) {
                    Link("Правила сообщества", destination: Legal.termsURL).font(.footnote)
                    Link("Политику конфиденциальности", destination: Legal.privacyPolicyURL).font(.footnote)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
