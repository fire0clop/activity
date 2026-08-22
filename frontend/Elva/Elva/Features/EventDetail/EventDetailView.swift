import MapKit
import SwiftUI

struct EventDetailView: View {
    let eventID: String
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var event: EventDetail?
    @State private var isLoading = true
    @State private var actionLoading = false
    @State private var errorText: String?
    @State private var showEdit = false
    @State private var showReport = false
    @State private var reportStatus: String?
    @State private var photoPage = 0
    @State private var fullScreen = false
    @State private var showInvite = false
    @State private var inviteResult: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()
            if let event {
                ScrollView(showsIndicators: false) { content(event) }
                    .ignoresSafeArea(edges: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) { stickyBar(event) }
            } else if isLoading {
                ProgressView().tint(Theme.accent)
            } else {
                Text(errorText ?? "Не найдено").foregroundStyle(Theme.ink2)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showEdit) {
            if let e = event { EventEditView(event: e) { Task { await load() } } }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            FullScreenPhotoView(images: event?.images ?? [], start: photoPage)
        }
        .sheet(isPresented: $showInvite) {
            InviteConnectionsView(eventID: eventID) { invited in
                inviteResult = invited > 0
                    ? "Позвали: \(invited). Придут, если подтвердят."
                    : "Никого не позвали."
                Task { await load() }
            }
        }
        .task { await load() }
        .confirmationDialog("Пожаловаться на событие", isPresented: $showReport, titleVisibility: .visible) {
            Button("Спам") { Task { await report("spam") } }
            Button("Неуместное содержание") { Task { await report("inappropriate") } }
            Button("Безопасность") { Task { await report("safety") } }
            Button("Другое") { Task { await report("other") } }
            Button("Отмена", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(_ e: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover(e)
            VStack(alignment: .leading, spacing: 18) {
                Text(e.title).font(.display(28)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                timeBlock(e)
                placeBlock(e)
                factsRow(e)
                if !e.acceptedParticipants.isEmpty { goingBlock(e) }
                organizerRow(e)
                if let d = e.description, !d.isEmpty {
                    Text(d).font(.system(size: 16)).foregroundStyle(Theme.ink.opacity(0.85)).lineSpacing(3)
                }
                if let reportStatus { Text(reportStatus).font(.footnote).foregroundStyle(Theme.ink2) }
                if e.status == "finished", e.isOrganizer || e.myParticipation?.status == "accepted" {
                    NavigationLink { ReviewView(event: e) } label: {
                        Label("Оставить отзывы", systemImage: "star.bubble").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentInk)
                    }
                }
                // Позвать тех, кого в приложении ещё нет: ссылка открывает эту же
                // карточку, а без приложения ведёт в App Store.
                if e.status != "cancelled" {
                    ShareLink(
                        item: AppConfig.shareURL(eventID: e.id),
                        subject: Text(e.title),
                        message: Text("Собираемся: «\(e.title)». Присоединяйся")
                    ) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentInk)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper)
            .clipShape(RoundedCorners(radius: 26, corners: [.topLeft, .topRight]))
            .offset(y: -24)
        }
    }

    // MARK: cover

    @ViewBuilder
    private func cover(_ e: EventDetail) -> some View {
        ZStack(alignment: .top) {
            Group {
                if !e.images.isEmpty {
                    TabView(selection: $photoPage) {
                        ForEach(Array(e.images.enumerated()), id: \.offset) { i, url in
                            CoverImage(url: url, category: e.category, height: 320).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: e.images.count > 1 ? .always : .never))
                    .onTapGesture { fullScreen = true }
                } else {
                    CategoryCover(category: e.category)
                }
            }
            .frame(height: 320).frame(maxWidth: .infinity).clipped()

            // top controls
            HStack {
                roundIcon("chevron.left") { dismiss() }
                    .accessibilityLabel("Назад")
                Spacer()
                CategoryBadge(category: e.category)
                Spacer()
                if e.isOrganizer {
                    roundIcon("pencil") { showEdit = true }
                        .accessibilityLabel("Редактировать событие")
                } else {
                    roundIcon("ellipsis") { showReport = true }
                        .accessibilityLabel("Пожаловаться на событие")
                }
            }
            .padding(.horizontal, 16).padding(.top, 56)
        }
    }

    private func roundIcon(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40).background(.white.opacity(0.92)).clipShape(Circle())
        }
    }

    // MARK: blocks

    @ViewBuilder
    private func timeBlock(_ e: EventDetail) -> some View {
        HStack(spacing: 12) {
            let p = DateFormat.dayPill(e.day)
            VStack(spacing: 0) {
                Text(p.num).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(p.month).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accentInk)
            }
            .frame(width: 54, height: 54).background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormat.prettyDay(e.day)).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                if e.timeDisclosed {
                    Text(DateFormat.time(e.startsAt) + " · точное время").font(.system(size: 13)).foregroundStyle(Theme.ink2)
                } else {
                    Text("время — после подтверждения").font(.system(size: 13)).foregroundStyle(Theme.ink2)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func placeBlock(_ e: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let addr = e.address { Label(addr, systemImage: "mappin.and.ellipse").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink) }
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: e.latitude, longitude: e.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                Marker(e.title, coordinate: CLLocationCoordinate2D(latitude: e.latitude, longitude: e.longitude))
            }
            .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false)
            if let map = e.mapURL, let u = URL(string: map) {
                Link(destination: u) { Label("Открыть в Яндекс.Картах", systemImage: "map.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentInk) }
            }
        }
    }

    @ViewBuilder
    private func factsRow(_ e: EventDetail) -> some View {
        let price = Pricing.detail(price: e.price, split: e.priceSplit,
                                   current: e.participantsCurrent, max: e.participantsMax)
        VStack(spacing: 8) {
            // Единый компонент метрик — тот же, что в статистике профиля.
            MetricsRow(items: [
                .init(value: "\(e.participantsCurrent)/\(e.participantsMax.map(String.init) ?? "∞")",
                      label: "участники"),
                .init(value: price.value, label: price.caption),
            ])
            // Общий счёт: цена меняется по мере набора — объясняем это прямо, а не мелким шрифтом.
            if PriceSplit(raw: e.priceSplit) == .shared, let total = e.price, total > 0 {
                Text("Общий счёт \(Pricing.amount(total)) делится на пришедших — чем больше людей, тем дешевле каждому.")
                    .font(.footnote).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func goingBlock(_ e: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УЖЕ ИДУТ").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(Theme.ink2)
            HStack(spacing: 10) {
                AvatarStack(urls: e.acceptedParticipants.map { $0.avatarURL },
                            names: e.acceptedParticipants.map { $0.name }, size: 38)
                Spacer()
                NavigationLink {
                    ParticipantsView(eventID: e.id, isOrganizer: e.isOrganizer)
                } label: {
                    Text("Все").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentInk)
                }
            }
        }
    }

    private func organizerRow(_ e: EventDetail) -> some View {
        NavigationLink { PublicProfileView(userID: e.organizer.id) } label: {
            HStack(spacing: 12) {
                AvatarCircle(url: e.organizer.avatarURL, name: e.organizer.name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Организатор").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink2)
                    Text(e.organizer.name ?? "—").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                // В карточке новичок помечен явно: это часть решения «идти или нет».
                RatingView(value: e.organizer.ratingAvg, count: e.organizer.reviewsCount,
                           showsNewcomer: true)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
            }
            .padding(14).cardStyle()
        }.buttonStyle(.plain)
    }

    // MARK: sticky CTA

    @ViewBuilder
    private func stickyBar(_ e: EventDetail) -> some View {
        VStack(spacing: 0) {
            Divider().background(Theme.line)
            // Ошибка живёт у кнопки, которая её вызвала, а не двумя экранами выше.
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.dangerInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8).padding(.horizontal, 20)
            }
            if let inviteResult {
                Text(inviteResult).font(.footnote).foregroundStyle(Theme.ink2)
                    .padding(.top, 8).padding(.horizontal, 20)
            }
            Group {
                if e.isOrganizer {
                    HStack(spacing: 10) {
                        NavigationLink {
                            ParticipantsView(eventID: e.id, isOrganizer: true)
                        } label: { ctaLabel("Участники", filled: true) }
                        // Позвать знакомых — самый быстрый способ собрать состав,
                        // когда движуха новая и в ленте её ещё никто не увидел.
                        Button { showInvite = true } label: {
                            ctaLabel("Позвать своих", filled: false)
                        }
                        .disabled(e.status == "cancelled" || e.status == "finished")
                    }
                } else {
                    switch ParticipationStatus(raw: e.myParticipation?.status) {
                    case .invited:
                        // Организатор уже сказал «да» — остаётся согласиться.
                        VStack(spacing: 6) {
                            Text("Вас позвали на эту движуху")
                                .font(.system(size: 13)).foregroundStyle(Theme.ink2)
                            HStack(spacing: 10) {
                                Button { Task { await join() } } label: {
                                    ctaLabel("Иду", filled: true, loading: actionLoading)
                                }
                                .disabled(actionLoading)
                                Button { Task { await leave() } } label: {
                                    ctaLabel("Не смогу", filled: false)
                                }
                                .disabled(actionLoading)
                            }
                        }
                    case .accepted:
                        if let cid = e.conversationID {
                            NavigationLink {
                                ChatView(conversationID: cid, title: e.title,
                                         isArchived: e.status == "finished")
                            } label: { ctaLabel("Вы участвуете · открыть чат", filled: true) }
                        } else { ctaLabel("Вы участвуете ✓", filled: false) }
                    case .pending: ctaLabel("Заявка отправлена", filled: false)
                    case .waitlisted: ctaLabel("Вы в листе ожидания", filled: false)
                    case .rejected, .cancelled, .unknown:
                        // Отклонённый/отменивший может откликнуться снова (бэк это допускает);
                        // .unknown (нет заявки или новый статус) — тоже показываем отклик.
                        Button { Task { await join() } } label: {
                            ctaLabel("Откликнуться", filled: true, loading: actionLoading)
                        }
                        .disabled(actionLoading)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        // Непрозрачный фон + мягкая тень сверху: контент уходит ПОД панель чисто,
        // а не просвечивает сквозь неё (раньше метрики «обрезались» полупрозрачным баром).
        .background(Theme.paper)
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: -3)
    }

    private func ctaLabel(_ title: String, filled: Bool, loading: Bool = false) -> some View {
        ZStack {
            if loading { ProgressView().tint(filled ? .white : Theme.ink2) }
            else { Text(title).font(.system(size: 17, weight: .bold)) }
        }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(filled ? Theme.accent : Theme.surface)
            .foregroundStyle(filled ? .white : Theme.ink2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(filled ? Color.clear : Theme.line))
    }

    // MARK: actions

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { event = try await auth.api.send(Endpoint(path: "/events/\(eventID)")) }
        catch let err as APIError { errorText = err.message } catch { errorText = "Ошибка загрузки" }
    }

    private func report(_ reason: String) async {
        reportStatus = nil; errorText = nil
        do {
            try await auth.api.sendVoid(Endpoint(
                path: "/reports", method: .post,
                body: ReportBody(target_user_id: nil, target_event_id: eventID, reason: reason, comment: nil)))
            reportStatus = "Жалоба отправлена. Спасибо."
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось отправить жалобу. Проверьте соединение."
        }
    }

    private func join() async {
        actionLoading = true; errorText = nil; defer { actionLoading = false }
        do {
            let _: JoinResponse = try await auth.api.send(Endpoint(path: "/events/\(eventID)/join", method: .post))
            Haptics.success()
            await load()
        } catch let err as APIError { errorText = err.message } catch { errorText = "Не удалось откликнуться" }
    }

    /// Отказаться от приглашения или выйти из состава.
    private func leave() async {
        actionLoading = true; errorText = nil; defer { actionLoading = false }
        do {
            try await auth.api.sendVoid(Endpoint(path: "/events/\(eventID)/join", method: .delete))
            await load()
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось отменить участие" }
    }
}

/// Скругление выбранных углов.
struct RoundedCorners: Shape {
    var radius: CGFloat = 20
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
