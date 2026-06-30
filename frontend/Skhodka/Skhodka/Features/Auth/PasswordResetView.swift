import SwiftUI

/// Смена/сброс пароля с подтверждением по SMS. Используется и при «забыли пароль», и в профиле.
struct PasswordResetView: View {
    var prefillPhone: String = ""
    var asSheet: Bool = false
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var phone = "+7"
    @State private var code = ""
    @State private var newPassword = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorText: String?
    @FocusState private var codeFocused: Bool

    private var phoneValid: Bool { phone.count >= 11 }
    private var canReset: Bool { code.count == 6 && newPassword.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Смена пароля").font(.title2).fontWeight(.bold).padding(.top)
                Text("Подтвердим номер кодом из SMS и установим новый пароль.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

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
                    TextField("Код из SMS", text: $code)
                        .textContentType(.oneTimeCode).focused($codeFocused)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                    SecureField("Новый пароль (от 6 символов)", text: $newPassword)
                        .textContentType(.newPassword)
                        .padding().background(Theme.secondaryBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    PrimaryButton(title: "Сменить пароль", isLoading: isLoading, isEnabled: canReset) {
                        Task { await reset() }
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
        .navigationTitle("Пароль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
            }
        }
        .onAppear { if !prefillPhone.isEmpty { phone = prefillPhone } }
    }

    private func sendCode() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            _ = try await auth.requestCode(phone: phone)
            codeSent = true
            codeFocused = true
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Нет соединения с сервером" }
    }

    private func reset() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            try await auth.resetPassword(phone: phone, code: code, newPassword: newPassword)
            if asSheet { dismiss() }
        } catch let err as APIError {
            errorText = err.message
            if err.code == "invalid_code" || err.code == "code_expired" { code = "" }
        } catch { errorText = "Нет соединения с сервером" }
    }
}
