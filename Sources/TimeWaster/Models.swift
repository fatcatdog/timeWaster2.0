import Foundation

struct TrackedSite: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var domains: [String]
    var dailyLimitMinutes: Int
    var iconName: String
    var colorHex: String
    var isEnabled: Bool = true
    var blockAppBundleIds: [String] = []

    var dailyLimitSeconds: Int {
        dailyLimitMinutes * 60
    }

    static let defaults: [TrackedSite] = [
        TrackedSite(
            name: "X / Twitter",
            domains: ["x.com", "twitter.com"],
            dailyLimitMinutes: 20,
            iconName: "bubble.left.and.bubble.right.fill",
            colorHex: "#1DA1F2"
        ),
        TrackedSite(
            name: "YouTube",
            domains: ["youtube.com", "youtu.be"],
            dailyLimitMinutes: 30,
            iconName: "play.rectangle.fill",
            colorHex: "#FF0000"
        ),
        TrackedSite(
            name: "Netflix",
            domains: ["netflix.com"],
            dailyLimitMinutes: 45,
            iconName: "film.fill",
            colorHex: "#E50914"
        ),
        TrackedSite(
            name: "Prime Video",
            domains: ["primevideo.com"],
            dailyLimitMinutes: 45,
            iconName: "tv.fill",
            colorHex: "#00A8E1",
            blockAppBundleIds: ["com.amazon.aiv.AIVApp"]
        ),
        TrackedSite(
            name: "Hulu / Disney+ / Max",
            domains: ["hulu.com", "disneyplus.com", "max.com", "hbomax.com"],
            dailyLimitMinutes: 45,
            iconName: "sparkles.tv.fill",
            colorHex: "#9B51E0"
        ),
        TrackedSite(
            name: "Reddit",
            domains: ["reddit.com"],
            dailyLimitMinutes: 15,
            iconName: "text.bubble.fill",
            colorHex: "#FF4500"
        )
    ]
}

struct DailyUsageRecord: Codable {
    var dateString: String // YYYY-MM-DD
    var secondsBySiteId: [UUID: Int] = [:]
    var bonusUntilBySiteId: [UUID: Date] = [:]

    func secondsUsed(for siteId: UUID) -> Int {
        secondsBySiteId[siteId] ?? 0
    }

    var totalSecondsUsed: Int {
        secondsBySiteId.values.reduce(0, +)
    }

    func hasActiveBonus(for siteId: UUID, now: Date = Date()) -> Bool {
        guard let expiry = bonusUntilBySiteId[siteId] else { return false }
        return expiry > now
    }
}

enum StrictnessMode: String, Codable, CaseIterable, Identifiable {
    case friction = "Friction Challenge (Type phrase to unlock 5m)"
    case hardLock = "Hard Lockout (No override until midnight)"

    var id: String { rawValue }
}

struct AppSettings: Codable {
    var globalDailyBudgetMinutes: Int = 90
    var useGlobalBudget: Bool = true
    var strictness: StrictnessMode = .friction
    var pauseTracking: Bool = false
    var warningMinutesBefore: Int = 2
}
