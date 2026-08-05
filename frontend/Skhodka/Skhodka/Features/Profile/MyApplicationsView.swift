import SwiftUI

/// Мои отклики одним списком.
///
/// Раньше статус заявки жил только внутри карточки события: откликнулся на три штуки —
/// и вспоминай, где что. Здесь всё сразу, ближайшее сверху.
struct MyApplicationsView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var items: [MyApplication] = []
    @State private var showHistory = false
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                picker
                if isLoading && items.isEmpty {
                    ProgressView().tint(Theme.accent).padding(.top, 40)
                } else if loadFailed {
                    ErrorState { Task { await load() } }
                } else if items.isEmpty {
                    EmptyState(
                        icon: showHistory ? "clock.arrow.circlepath" : "paperplane",
                        title: showHistory ? "Здесь будет история" : "Заявок пока нет",
                        subtitle: showHistory
                            ? "Отклики, которые отменили или по которым отказали."
                            : "Откликнитесь на движуху в ленте — статус появится здесь."
                    )
                } else {
                    ForEach(items) { row($0) }
                }
            }
            .padding(16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Мои заявки")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: showHistory) { Task { await load() } }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            chip("Активные", selected: !showHistory) { showHistory = false }
            chip("История", selected: showHistory) { showHistory = true }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.ink2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Theme.line))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: MyApplication) -> some View {
        NavigationLink { EventDetailView(eventID: item.event.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CategoryBadge(category: item.event.category, compact: true)
                        statusPill(ParticipationStatus(raw: item.status))
                    }
                    Text(item.event.title)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(subtitle(item))
                        .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.ink2)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(CardButtonStyle())
    }

    private func subtitle(_ item: MyApplication) -> String {
        var parts = [DateFormat.prettyDay(item.event.day)]
        if let name = item.event.organizer.name { parts.append(name) }
        if let max = item.event.participantsMax {
            parts.append("\(item.event.participantsCurrent)/\(max)")
        } else {
            parts.append("\(item.event.participantsCurrent)/∞")
        }
        return parts.joined(separator: " · ")
    }

    /// Цвет несёт смысл: зелёное — место есть, жёлтое — ждём, серое — очередь, красное — мимо.
    private func statusPill(_ status: ParticipationStatus) -> some View {
        let color: Color = switch status {
        case .accepted: Theme.accent
        case .invited: Theme.accentInk
        case .pending: Theme.star
        case .waitlisted: Theme.ink2
        case .rejected, .cancelled, .unknown: Theme.danger
        }
        return Text(status.label)
            .font(.system(size: 11, weight: .heavy)).tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // «История» — то, что уже не действует: отказ и собственная отмена.
        let statuses = showHistory ? ["rejected", "cancelled"] : [nil]
        do {
            var collected: [MyApplication] = []
            for status in statuses {
                let query = status.map { ["status": $0] } ?? [:]
                let resp: MyApplicationsResponse = try await auth.api.send(
                    Endpoint(path: "/participations/mine", query: query))
                collected += resp.items
            }
            items = collected
            loadFailed = false
        } catch {
            loadFailed = items.isEmpty
        }
    }
}
