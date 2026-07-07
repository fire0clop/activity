import CoreLocation
import PhotosUI
import SwiftUI

struct EventCreateView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var category = ""
    @State private var startsAt = Date().addingTimeInterval(3600 * 3)
    @State private var mapURL = ""
    @State private var picked: CLLocationCoordinate2D?
    @State private var showPicker = false
    @State private var address = ""
    @State private var unlimited = false
    @State private var maxParticipants = 4
    @State private var price = ""
    @State private var autoAccept = false
    @State private var repeatWeekly = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var hasLocation: Bool {
        picked != nil || !mapURL.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 3 && hasLocation
    }

    var body: some View {
        Form {
            Section("Что и когда") {
                TextField("Название (напр. «Гидроциклы»)", text: $title)
                DatePicker("Начало", selection: $startsAt, in: Date()...)
            }
            Section("Категория") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Categories.pickable, id: \.self) { key in
                            categoryChip(key)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Section("Где") {
                Button {
                    showPicker = true
                } label: {
                    Label(picked == nil ? "Выбрать точку на карте" : "Точка выбрана на карте ✓",
                          systemImage: "mappin.and.ellipse")
                }
                if let p = picked {
                    Text(String(format: "Координаты: %.5f, %.5f", p.latitude, p.longitude))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text("или вставьте ссылку из Яндекс.Карт:").font(.caption).foregroundStyle(.secondary)
                TextField("Ссылка на точку из Яндекс.Карт", text: $mapURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: mapURL) { _, new in
                        if !new.trimmingCharacters(in: .whitespaces).isEmpty { picked = nil }
                    }

                TextField("Подсказка к месту (напр. «у пирса №3»)", text: $address)
            }
            Section("Компания") {
                Toggle("Без ограничения по людям", isOn: $unlimited)
                if !unlimited {
                    Stepper("Максимум: \(maxParticipants)", value: $maxParticipants, in: 2...100)
                }
                Toggle("Авто-приём первых", isOn: $autoAccept)
                Toggle("Повторять еженедельно", isOn: $repeatWeekly)
                TextField("Стоимость, ₽ (опционально)", text: $price).keyboardType(.numberPad)
            }
            Section("Фото (до 5)") {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                    Label("Добавить фото", systemImage: "photo.on.rectangle.angled")
                }
                if !photoImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(photoImages.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            Section("Описание") {
                TextField("Формат, что взять, бюджет", text: $description, axis: .vertical)
                    .lineLimit(3...8)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            Section {
                PrimaryButton(title: "Опубликовать", isLoading: isLoading, isEnabled: canSubmit) {
                    Task { await submit() }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Новое событие")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .sheet(isPresented: $showPicker) {
            MapPickerView { coord in
                picked = coord
                mapURL = ""
            }
        }
    }

    private func categoryChip(_ key: String) -> some View {
        let c = Categories.of(key)
        let selected = category == key
        return Button {
            category = selected ? "" : key
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: c.icon).font(.system(size: 12, weight: .bold))
                Text(c.title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : c.color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? c.color : c.color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                images.append(img)
            }
        }
        photoImages = images
    }

    private func submit() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        let iso = ISO8601DateFormatter()
        let body = CreateEventBody(
            title: title,
            description: description.isEmpty ? nil : description,
            category: category.isEmpty ? nil : category,
            starts_at: iso.string(from: startsAt),
            ends_at: nil,
            map_url: picked == nil ? mapURL.trimmingCharacters(in: .whitespaces) : nil,
            latitude: picked?.latitude,
            longitude: picked?.longitude,
            address: address.isEmpty ? nil : address,
            min_participants: 2,
            max_participants: unlimited ? nil : maxParticipants,
            price: Double(price),
            price_split: price.isEmpty ? "free" : "shared",
            auto_accept: autoAccept,
            recurrence: repeatWeekly ? "weekly" : "none"
        )
        do {
            let created: EventDetail = try await auth.api.send(Endpoint(
                path: "/events", method: .post, body: body))
            // Загружаем фото к созданному событию.
            for img in photoImages {
                if let jpeg = img.jpegData(compressionQuality: 0.85) {
                    let _: PhotosResponse = try await auth.api.upload(
                        path: "/events/\(created.id)/photos", fileData: jpeg,
                        fileName: "photo.jpg", mimeType: "image/jpeg")
                }
            }
            Haptics.success()
            dismiss()
        } catch let err as APIError {
            errorText = err.message
        } catch { errorText = "Не удалось создать событие" }
    }
}
