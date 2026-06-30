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
    @State private var photoPage = 0
    @State private var fullScreen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()
            if let event {
                ScrollView(showsIndicators: false) { content(event) }
                    .ignoresSafeArea(edges: .top)
                stickyBar(event)
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
        .task { await load() }
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
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
                if e.status == "finished", e.isOrganizer || e.myParticipation?.status == "accepted" {
                    NavigationLink { ReviewView(event: e) } label: {
                        Label("Оставить отзывы", systemImage: "star.bubble").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Color.clear.frame(height: 90)
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
                            AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFill() } placeholder: { CategoryCover(category: e.category) }
                                .tag(i).clipped()
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
                Spacer()
                CategoryBadge(category: e.category)
                Spacer()
                if e.isOrganizer { roundIcon("pencil") { showEdit = true } } else { Color.clear.frame(width: 40, height: 40) }
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
                Text(p.month).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accent)
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
                Link(destination: u) { Label("Открыть в Яндекс.Картах", systemImage: "map.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent) }
            }
        }
    }

    private func factsRow(_ e: EventDetail) -> some View {
        HStack(spacing: 10) {
            factChip("person.2.fill", "\(e.participantsCurrent)/\(e.participantsMax.map(String.init) ?? "∞")", "участники")
            if let p = e.price, p > 0 { factChip("rublesign", "\(Int(p))", e.priceSplit == "shared" ? "на всех" : "с человека") }
            else { factChip("gift.fill", "Free", "бесплатно") }
        }
    }

    private func factChip(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func goingBlock(_ e: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УЖЕ ИДУТ").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(Theme.ink2)
            HStack(spacing: 10) {
                AvatarStack(urls: e.acceptedParticipants.map { $0.avatarURL },
                            names: e.acceptedParticipants.map { $0.name }, size: 38)
                Spacer()
                NavigationLink { ParticipantsView(eventID: e.id) } label: {
                    Text("Все").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
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
                RatingView(value: e.organizer.ratingAvg, count: 0)
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
            Group {
                if e.isOrganizer {
                    NavigationLink { ParticipantsView(eventID: e.id) } label: { ctaLabel("Управлять участниками", filled: true) }
                } else {
                    switch e.myParticipation?.status {
                    case "accepted":
                        if let cid = e.conversationID {
                            NavigationLink { ChatView(conversationID: cid, title: e.title) } label: { ctaLabel("Вы участвуете · открыть чат", filled: true) }
                        } else { ctaLabel("Вы участвуете ✓", filled: false) }
                    case "pending": ctaLabel("Заявка отправлена", filled: false)
                    case "waitlisted": ctaLabel("Вы в листе ожидания", filled: false)
                    default:
                        Button { Task { await join() } } label: { ctaLabel(actionLoading ? "…" : "Откликнуться", filled: true) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        .background(Theme.paper.opacity(0.98))
    }

    private func ctaLabel(_ title: String, filled: Bool) -> some View {
        Text(title).font(.system(size: 17, weight: .bold))
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

    private func join() async {
        actionLoading = true; errorText = nil; defer { actionLoading = false }
        do {
            let _: JoinResponse = try await auth.api.send(Endpoint(path: "/events/\(eventID)/join", method: .post))
            await load()
        } catch let err as APIError { errorText = err.message } catch { errorText = "Не удалось откликнуться" }
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
