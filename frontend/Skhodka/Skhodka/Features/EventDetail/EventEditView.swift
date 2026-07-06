import PhotosUI
import SwiftUI

struct EventEditView: View {
    let event: EventDetail
    var onChanged: () -> Void
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var category: String
    @State private var startsAt: Date
    @State private var unlimited: Bool
    @State private var maxParticipants: Int
    @State private var price: String
    @State private var autoAccept: Bool
    @State private var newMapURL = ""
    @State private var photos: [String]
    @State private var newPhoto: PhotosPickerItem?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(event: EventDetail, onChanged: @escaping () -> Void) {
        self.event = event
        self.onChanged = onChanged
        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description ?? "")
        _category = State(initialValue: event.category ?? "")
        _startsAt = State(initialValue: DateFormat.parse(event.startsAt) ?? Date())
        _unlimited = State(initialValue: event.participantsMax == nil)
        _maxParticipants = State(initialValue: event.participantsMax ?? 4)
        _price = State(initialValue: event.price.map { String(Int($0)) } ?? "")
        _autoAccept = State(initialValue: event.autoAccept)
        _photos = State(initialValue: event.photoURLs)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Что и когда") {
                    TextField("Название", text: $title)
                    TextField("Категория", text: $category)
                    DatePicker("Начало", selection: $startsAt, in: Date()...)
                }
                Section("Где") {
                    TextField("Новая ссылка Яндекс.Карт (если менять)", text: $newMapURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Компания") {
                    Toggle("Без ограничения", isOn: $unlimited)
                    if !unlimited {
                        Stepper("Максимум: \(maxParticipants)", value: $maxParticipants, in: 2...100)
                    }
                    Toggle("Авто-приём первых", isOn: $autoAccept)
                    TextField("Стоимость, ₽", text: $price).keyboardType(.numberPad)
                }
                Section("Фото") {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(photos, id: \.self) { p in
                                    photoThumb(p)
                                }
                            }
                        }
                    }
                    if photos.count < 5 {
                        PhotosPicker(selection: $newPhoto, matching: .images) {
                            Label("Добавить фото", systemImage: "plus")
                        }
                    }
                }
                Section("Описание") {
                    TextField("Описание", text: $description, axis: .vertical).lineLimit(3...8)
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Удалить событие", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { Task { await save() } }.disabled(isLoading)
                }
            }
            .onChange(of: newPhoto) { _, item in Task { await addPhoto(item) } }
            .confirmationDialog("Удалить событие?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { Task { await deleteEvent() } }
                Button("Отмена", role: .cancel) {}
            }
        }
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
        let iso = ISO8601DateFormatter()
        let trimmedLink = newMapURL.trimmingCharacters(in: .whitespaces)
        let body = UpdateEventBody(
            title: title,
            description: description.isEmpty ? nil : description,
            category: category.isEmpty ? nil : category,
            starts_at: iso.string(from: startsAt),
            map_url: trimmedLink.isEmpty ? nil : trimmedLink,
            address: nil,
            max_participants: unlimited ? nil : maxParticipants,
            price: Double(price),
            price_split: price.isEmpty ? "free" : "shared",
            auto_accept: autoAccept
        )
        do {
            let _: EventDetail = try await auth.api.send(Endpoint(
                path: "/events/\(event.id)", method: .patch, body: body))
            onChanged(); dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось сохранить" }
    }

    private func addPhoto(_ item: PhotosPickerItem?) async {
        defer { newPhoto = nil }
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) else { return }
        errorText = nil
        do {
            let resp: PhotosResponse = try await auth.api.upload(
                path: "/events/\(event.id)/photos", fileData: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg")
            photos = resp.photoURLs; onChanged()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось загрузить фото" }
    }

    private func removePhoto(_ url: String) async {
        errorText = nil
        do {
            let resp: PhotosResponse = try await auth.api.send(Endpoint(
                path: "/events/\(event.id)/photos", method: .delete, query: ["url": url]))
            photos = resp.photoURLs; onChanged()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось удалить фото" }
    }

    private func deleteEvent() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            try await auth.api.sendVoid(Endpoint(path: "/events/\(event.id)", method: .delete))
            onChanged(); dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось удалить событие" }
    }
}
