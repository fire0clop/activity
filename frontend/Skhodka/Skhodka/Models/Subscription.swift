import Foundation

/// Подписка на новые события (категория и/или гео-область).
struct Subscription: Decodable, Identifiable, Hashable {
    let id: String
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let radiusKm: Double

    private enum CodingKeys: String, CodingKey {
        case id, category, latitude, longitude
        case radiusKm = "radius_km"
    }
}

struct SubscriptionsResponse: Decodable {
    let items: [Subscription]
}

struct SubscriptionCreateBody: Encodable {
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let radius_km: Double
}
