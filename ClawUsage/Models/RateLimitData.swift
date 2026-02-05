import Foundation

struct UsageBucket: Decodable {
    let utilization: Double // 0-100
    let resets_at: String?

    var usagePercent: Double {
        utilization / 100.0
    }

    var resetDate: Date? {
        guard let resets_at = resets_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resets_at) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resets_at)
    }
}

struct UsageData: Decodable {
    let five_hour: UsageBucket?
    let seven_day: UsageBucket?

    /// The higher of the two buckets, used for the menu bar icon
    var maxUsagePercent: Double {
        max(five_hour?.usagePercent ?? 0, seven_day?.usagePercent ?? 0)
    }

    static let empty = UsageData(five_hour: nil, seven_day: nil)

    static func relativeTime(to date: Date?) -> String {
        guard let date = date else { return "unknown" }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "in <1 min" }
        if minutes == 1 { return "in 1 min" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        if hours == 1 { return "in 1 hr" }
        return "in \(hours) hr"
    }

    static func formatResetDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "N/A" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }
        guard let date = date else { return dateString }
        let display = DateFormatter()
        display.dateStyle = .none
        display.timeStyle = .short
        return display.string(from: date)
    }
}
