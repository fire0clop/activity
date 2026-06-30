import PhotosUI
import SwiftUI

/// Обязательный онбординг: без имени, фото и «о себе» действия в приложении запрещены (403 profile_incomplete).
struct OnboardingView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var name = ""
    @State private var bio = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !bio.trimmingCharacters(in: .whitespaces).isEmpty
            && avatarImage != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Расскажите о себе")
                        .font(.title2).fontWeight(.bold)
                    Text("Фото и пара слов нужны, чтобы другие вам доверяли. Без этого нельзя создавать события и откликаться.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack {
                            if let avatarImage {
                                Image(uiImage: avatarImage).resizable().scaledToFill()
                            } else {
                                Image(systemName: "camera.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 120, height: 120)
                        .background(Theme.secondaryBg)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Имя").font(.footnote).foregroundStyle(.secondary)
                        TextField("Как вас зовут", text: $name)
                            .padding().background(Theme.secondaryBg)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("О себе").font(.footnote).foregroundStyle(.secondary)
                        TextField("Чем увлекаетесь, что любите", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                            .padding().background(Theme.secondaryBg)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }

                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }

                    PrimaryButton(title: "Готово", isLoading: isLoading, isEnabled: canSubmit) {
                        Task { await submit() }
                    }
                }
                .padding()
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Выйти") { auth.signOut() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task { await loadImage(item) }
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        avatarImage = img
    }

    private func submit() async {
        guard let img = avatarImage, let jpeg = img.jpegData(compressionQuality: 0.85) else { return }
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            let _: UserPrivate = try await auth.api.send(Endpoint(
                path: "/users/me", method: .patch,
                body: UpdateProfileBody(name: name, bio: bio, birth_date: nil, gender: nil)
            ))
            let _: AvatarResponse = try await auth.api.upload(
                path: "/users/me/avatar", fileData: jpeg,
                fileName: "avatar.jpg", mimeType: "image/jpeg"
            )
            await auth.refreshMe()
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось сохранить профиль"
        }
    }
}
