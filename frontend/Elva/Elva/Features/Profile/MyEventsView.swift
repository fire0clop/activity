import SwiftUI

/// «Мои события»: организованные и те, где участвую, включая завершённые (история).
struct MyEventsView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var items: [EventListItem] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(Theme.accent)
            } else if let errorText, items.isEmpty {
                stateBlock(icon: "wifi.slash", title: errorText, action: "Повторить") {
                    Task { await load() }
                }
            } else if items.isEmpty {
                stateBlock(icon: "calendar", title: "Событий пока нет", action: nil, perform: nil)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink { EventDetailView(eventID: item.id) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Мои события")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ item: EventListItem) -> some View {
        HStack(spacing: 12) {
            cover(item)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink).lineLimit(1)
                Text(item.day).font(.system(size: 13)).foregroundStyle(Theme.ink2)
                statusBadge(item.status)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }

    @ViewBuilder
    private func cover(_ item: EventListItem) -> some View {
        if let first = item.images.first, let url = URL(string: first) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Theme.secondaryBg)
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "calendar").foregroundStyle(Theme.ink2))
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "open": ("Открыто", Theme.accent)
        case "full": ("Мест нет", Theme.ink2)
        case "finished": ("Завершено", Theme.ink2)
        case "cancelled": ("Отменено", .red)
        default: (status, Theme.ink2)
        }
        return Text(label).font(.system(size: 11, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    @ViewBuilder
    private func stateBlock(icon: String, title: String, action: String?, perform: (() -> Void)?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.ink2)
            Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            if let action, let perform {
                Button(action: perform) {
                    Text(action).font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: EventListResponse = try await auth.api.send(Endpoint(path: "/events/mine"))
            items = resp.items
            errorText = nil
        } catch let err as APIError { errorText = err.message }
        catch { errorText = "Не удалось загрузить события. Проверьте соединение." }
    }
}
