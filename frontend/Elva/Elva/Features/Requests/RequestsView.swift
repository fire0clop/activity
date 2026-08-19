import CoreLocation
import SwiftUI

/// Лента желаний: чего люди рядом хотят, но пока никто не организовал.
///
/// Здесь дешёвая сторона продукта. Завести событие — это время, место, состав и
/// ответственность; сказать «хочу на теннис где-то на неделе» — пятнадцать секунд.
/// Готовых заявить желание всегда больше, чем готовых организовать, поэтому именно
/// отсюда пустая лента наполняется первой.
struct RequestsView: View {
    let coordinate: CLLocationCoordinate2D
    var areaHint: String?
    /// Внутри страницы ленты свой заголовок и тулбар не нужны — они уже есть сверху.
    var embedded: Bool = false
    /// Внутри ленты «+» живёт в общей шапке, поэтому создание запускается снаружи.
    var showCreate: Binding<Bool>? = nil

    @EnvironmentObject var auth: AuthManager
    @State private var items: [CompanyRequest] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorText: String?
    @State private var showCreateInternal = false
    @State private var organizing: CompanyRequest?

    private var createBinding: Binding<Bool> { showCreate ?? $showCreateInternal }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: FeedLayout.cardGap) {
                header
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                }
                if isLoading && items.isEmpty {
                    ProgressView().tint(Theme.accent).padding(.top, 40)
                } else if loadFailed {
                    ErrorState { Task { await load() } }
                } else if items.isEmpty {
                    EmptyState(
                        icon: "hand.raised.fill",
                        title: "Пока никто ничего не хочет",
                        subtitle: "Скажите первым, чем хотели бы заняться. Это ни к чему не обязывает — организовать может кто угодно.",
                        actionTitle: "Сказать, чего хочу",
                        action: { createBinding.wrappedValue = true }
                    )
                } else {
                    ForEach(items) { card($0) }
                }
            }
            .padding(.horizontal, FeedLayout.gutter)
            .padding(.top, FeedLayout.top)
            .padding(.bottom, FeedLayout.bottom)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(embedded ? "" : "Ищут компанию")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createBinding.wrappedValue = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: createBinding) {
            CreateRequestView(coordinate: coordinate, areaHint: areaHint) {
                Task { await load() }
            }
        }
        .sheet(item: $organizing) { req in
            NavigationStack {
                EventCreateView(
                    prefill: EventCreateView.Prefill(
                        category: req.category,
                        coordinate: CLLocationCoordinate2D(latitude: req.latitude,
                                                           longitude: req.longitude),
                        address: req.area,
                        fromRequestID: req.id
                    )
                )
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        Text(embedded
             ? "Живой спрос: возьмите на себя то, чего хотят несколько человек."
             : "Здесь видно живой спрос: возьмите на себя то, чего хотят несколько человек, — и состав соберётся сам.")
            .font(.footnote).foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }

    private func card(_ r: CompanyRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CategoryBadge(category: r.category, style: .tinted)
                Text(WhenWindow(rawValue: r.whenWindow)?.title ?? "На неделе")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.secondaryBg, in: Capsule())
                Spacer()
                if r.supportsCount > 0 {
                    Text("хотят \(r.supportsCount + 1)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentInk)
                }
            }

            if let text = r.text, !text.isEmpty {
                Text(text).font(.system(size: 15)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                AvatarCircle(url: r.author.avatarURL, name: r.author.name, size: 22)
                Text(r.author.name ?? "Кто-то").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                if let area = r.area {
                    Text("· \(area)").font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
                } else if let d = r.distanceKm {
                    Text("· \(String(format: "%.1f км", d))")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
            }

            if r.isMine {
                Button(role: .destructive) { Task { await cancel(r) } } label: {
                    Text("Снять запрос").font(.system(size: 13, weight: .semibold))
                }
            } else {
                HStack(spacing: 10) {
                    Button { organizing = r } label: {
                        Text("Беру на себя")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radii.sm))
                    }
                    Button { Task { await toggleSupport(r) } } label: {
                        Text(r.iSupport ? "Я тоже ✓" : "Я тоже хочу")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(r.iSupport ? Theme.accentInk : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(r.iSupport ? Theme.accentSoft : Theme.secondaryBg,
                                        in: RoundedRectangle(cornerRadius: Radii.sm))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: CompanyRequestsResponse = try await auth.api.send(Endpoint(
                path: "/requests",
                query: ["lat": "\(coordinate.latitude)", "lng": "\(coordinate.longitude)",
                        "radius_km": "25"]))
            items = resp.items
            errorText = nil; loadFailed = false
        } catch let err as APIError {
            errorText = err.message; loadFailed = items.isEmpty
        } catch {
            loadFailed = items.isEmpty
        }
    }

    private func toggleSupport(_ r: CompanyRequest) async {
        errorText = nil
        do {
            let _: SupportResponse = try await auth.api.send(Endpoint(
                path: "/requests/\(r.id)/support", method: r.iSupport ? .delete : .post))
            Haptics.tap()
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось отметить желание." }
    }

    private func cancel(_ r: CompanyRequest) async {
        errorText = nil
        do {
            try await auth.api.sendVoid(Endpoint(path: "/requests/\(r.id)", method: .delete))
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось снять запрос." }
    }
}

/// Заявить желание. Полей минимум — в этом весь смысл экрана.
struct CreateRequestView: View {
    let coordinate: CLLocationCoordinate2D
    var areaHint: String?
    /// Внутри страницы ленты свой заголовок и тулбар не нужны — они уже есть сверху.
    var embedded: Bool = false
    /// Внутри ленты «+» живёт в общей шапке, поэтому создание запускается снаружи.
    var showCreate: Binding<Bool>? = nil
    var onCreated: () -> Void = {}

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var category = "walk"
    @State private var text = ""
    @State private var area = ""
    @State private var window: WhenWindow = .week
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FormSection(title: "Чем заняться") {
                        CategoryPicker(selection: $category)
                    }
                    FormSection(title: "Когда примерно") {
                        Picker("Когда", selection: $window) {
                            ForEach(WhenWindow.allCases) { w in Text(w.title).tag(w) }
                        }
                        .pickerStyle(.segmented)
                    }
                    FormSection(title: "Подробности") {
                        TextField("Например: «хочу на теннис вечером, ракетка есть»",
                                  text: $text, axis: .vertical)
                            .lineLimit(2...5)
                        FormDivider()
                        TextField("Район (необязательно)", text: $area)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    Text("Это не событие: время и место появятся, если кто-то возьмёт вашу идею на себя. Желание живёт до конца выбранного срока.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center).padding(.horizontal, 12)
                }
                .padding(16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Чего хочется?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSending ? "…" : "Сказать") { Task { await submit() } }
                        .disabled(isSending)
                }
            }
            .onAppear { if area.isEmpty, let hint = areaHint { area = hint } }
        }
    }

    private func submit() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let areaTrimmed = area.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: CompanyRequest = try await auth.api.send(Endpoint(
                path: "/requests", method: .post,
                body: CompanyRequestCreateBody(
                    category: category,
                    text: trimmed.isEmpty ? nil : trimmed,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    area: areaTrimmed.isEmpty ? nil : areaTrimmed,
                    radius_km: 10,
                    when_window: window.rawValue)))
            Haptics.success()
            onCreated()
            dismiss()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось отправить. Попробуйте ещё раз." }
    }
}
