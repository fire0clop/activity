import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var bio: String
    @State private var gender: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var photos: [String]
    @State private var avatarItem: PhotosPickerItem?
    @State private var newPhoto: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?

    private let genders = ["male": "Мужской", "female": "Женский",
                           "other": "Другой", "unspecified": "Не указан"]

    init(me: UserPrivate) {
        _name = State(initialValue: me.name ?? "")
        _bio = State(initialValue: me.bio ?? "")
        _gender = State(initialValue: me.gender)
        _hasBirthDate = State(initialValue: me.birthDate != nil)
        _birthDate = State(initialValue: EditProfileView.parseDay(me.birthDate) ?? Date(timeIntervalSince1970: 0))
        _photos = State(initialValue: me.photoURLs)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            avatarView.frame(width: 96, height: 96)
                        }
                        Spacer()
                    }
                }
                Section("О себе") {
                    TextField("Имя", text: $name)
                    TextField("О себе", text: $bio, axis: .vertical).lineLimit(3...6)
                    Picker("Пол", selection: $gender) {
                        ForEach(["male", "female", "other", "unspecified"], id: \.self) { g in
                            Text(genders[g] ?? g).tag(g)
                        }
                    }
                    Toggle("Указать дату рождения", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Дата рождения", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section("Мои фото") {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(photos, id: \.self) { photoThumb($0) } }
                        }
                    }
                    if photos.count < 5 {
                        PhotosPicker(selection: $newPhoto, matching: .images) {
                            Label("Добавить фото", systemImage: "plus")
                        }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(isLoading)
                }
            }
            .onChange(of: avatarItem) { _, item in Task { await changeAvatar(item) } }
            .onChange(of: newPhoto) { _, item in Task { await addPhoto(item) } }
        }
    }

    private var avatarView: some View {
        Group {
            if let avatarPreview {
                Image(uiImage: avatarPreview).resizable().scaledToFill()
            } else if let url = auth.me?.avatarURL, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
            } else {
                Theme.secondaryBg.overlay(Image(systemName: "camera.fill").foregroundStyle(.secondary))
            }
        }.clipShape(Circle())
    }

    private func photoThumb(_ p: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let u = URL(string: p) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
                    .frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button { Task { await removePhoto(p) } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
            }.padding(2)
        }
    }

    private func save() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        let body = UpdateProfileBody(
            name: name, bio: bio,
            birth_date: hasBirthDate ? EditProfileView.dayString(birthDate) : nil,
            gender: gender)
        do {
            let _: UserPrivate = try await auth.api.send(Endpoint(
                path: "/users/me", method: .patch, body: body))
            await auth.refreshMe()
            dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось сохранить" }
    }

    private func changeAvatar(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) else { return }
        avatarPreview = img
        let _: AvatarResponse? = try? await auth.api.upload(
            path: "/users/me/avatar", fileData: jpeg, fileName: "avatar.jpg", mimeType: "image/jpeg")
        await auth.refreshMe()
    }

    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) else { return }
        if let resp: PhotosResponse = try? await auth.api.upload(
            path: "/users/me/photos", fileData: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg") {
            photos = resp.photoURLs
        }
        newPhoto = nil
    }

    private func removePhoto(_ url: String) async {
        if let resp: PhotosResponse = try? await auth.api.send(Endpoint(
            path: "/users/me/photos", method: .delete, query: ["url": url])) {
            photos = resp.photoURLs
        }
    }

    private static func parseDay(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }
}
