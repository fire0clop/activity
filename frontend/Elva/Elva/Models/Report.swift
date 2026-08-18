import Foundation

struct ReportBody: Encodable {
    var target_user_id: String?
    var target_event_id: String?
    var reason: String          // spam | inappropriate | safety | other
    var comment: String?
}
