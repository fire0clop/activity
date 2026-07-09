import SwiftUI

/// Регистрация пошагово: номер → подтверждение кода → пароль.
struct RegisterView: View {
    @EnvironmentObject var auth: AuthManager

    private enum Step: Int { case phone = 0, code = 1, password = 2 }
    @State private var step: Step = .phone
    @State private var phone = "+7"
    @State private var code = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var verificationToken = ""
    @State private var isLoading = false
    @State private var resendIn = 0
    @State private var errorText: String?
    @FocusState private var codeFocused: Bool

    init() {
        #if DEBUG
        // Headless-скриншоты: старт с нужного шага (register:code / register:password).
        if let r = ProcessInfo.processInfo.environment["UITEST_ROUTE"] {
            if r.hasSuffix(":code") {
                _step = State(initialValue: .code); _phone = State(initialValue: "+79991234567")
            } else if r.hasSuffix(":password") {
                _step = State(initialValue: .password); _phone = State(initialValue: "+79991234567")
            }
        }
        #endif
    }

    private var phoneValid: Bool { phone.count >= 12 }          // +7 и 10 цифр
    private var codeValid: Bool { code.count == 6 }
    private var passwordValid: Bool { password.count >= 6 && acceptedTerms }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                stepDots
                Group {
                    switch step {
                    case .phone: phoneStep
                    case .code: codeStep
                    case .password: passwordStep
                    }
                }
                .transition(.opacity)
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .animation(.easeInOut(duration: 0.22), value: step)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Индикатор шага

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i <= step.rawValue ? Theme.accent : Theme.line)
                    .frame(width: i == step.rawValue ? 22 : 8, height: 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Шаг 1: номер

    private var phoneStep: some View {
        VStack(spacing: 16) {
            header("Ваш номер", "Пришлём код подтверждения в SMS")
            TextField("+79991234567", text: $phone)
                .keyboardType(.phonePad).textContentType(.telephoneNumber)
                .modifier(FieldStyle())
            PrimaryButton(title: "Получить код", isLoading: isLoading, isEnabled: phoneValid) {
                Task { await sendCode() }
            }
        }
    }

    // MARK: - Шаг 2: код

    private var codeStep: some View {
        VStack(spacing: 16) {
            header("Подтвердите номер", "Код отправлен на \(phone)")
            TextField("Код из SMS", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .focused($codeFocused)
                .modifier(FieldStyle())
                .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
            Button(resendIn > 0 ? "Отправить код повторно (\(resendIn))" : "Отправить код повторно") {
                Task { await sendCode() }
            }
            .font(.footnote).foregroundStyle(resendIn > 0 ? Theme.ink2 : Theme.accentInk).disabled(resendIn > 0)

            PrimaryButton(title: "Подтвердить", isLoading: isLoading, isEnabled: codeValid) {
                Task { await verify() }
            }
            Button("Изменить номер") { withAnimation { step = .phone }; errorText = nil }
                .font(.footnote).foregroundStyle(Theme.ink2)
        }
    }

    // MARK: - Шаг 3: пароль

    private var passwordStep: some View {
        VStack(spacing: 16) {
            header("Придумайте пароль", "Он понадобится для входа в аккаунт")
            SecureField("Пароль (от 6 символов)", text: $password)
                .textContentType(.newPassword)
                .modifier(FieldStyle())
            consentRow
            PrimaryButton(title: "Создать аккаунт", isLoading: isLoading, isEnabled: passwordValid) {
                Task { await register() }
            }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.serifTitle(26, weight: .bold)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
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
                Text("Создавая аккаунт, я принимаю:").font(.footnote).foregroundStyle(Theme.ink2)
                HStack(spacing: 12) {
                    Link("Правила сообщества", destination: Legal.termsURL).font(.footnote)
                    Link("Политику", destination: Legal.privacyPolicyURL).font(.footnote)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Действия

    private func sendCode() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await auth.requestCode(phone: phone)
            startResendTimer(resp.resendAfterSec)
            withAnimation { step = .code }
            codeFocused = true
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Нет соединения с сервером" }
    }

    private func verify() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await auth.verifyCode(phone: phone, code: code)
            if !resp.isNewUser {
                errorText = "Этот номер уже зарегистрирован — войдите по паролю."
                return
            }
            verificationToken = resp.verificationToken
            withAnimation { step = .password }
        } catch let err as APIError {
            errorText = err.message
            if err.isCode(.invalidCode) || err.isCode(.codeExpired) { code = "" }
        } catch { errorText = "Нет соединения с сервером" }
    }

    private func register() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            try await auth.register(verificationToken: verificationToken, password: password)
        } catch let err as APIError {
            errorText = err.message
            // Тикет протух — вернём на шаг кода.
            if err.isCode(.unauthorized) { withAnimation { step = .code } }
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
