import Foundation
import SwiftUI
import AppKit

@MainActor
final class TimeTrackerManager: ObservableObject {
    static let shared = TimeTrackerManager()

    @Published var sites: [TrackedSite] = [] {
        didSet { saveSites() }
    }
    @Published var settings: AppSettings = AppSettings() {
        didSet { saveSettings() }
    }
    @Published var todayRecord: DailyUsageRecord
    @Published var activeSite: TrackedSite?
    @Published var lastDetectedURL: String?

    private var timer: Timer?
    private var warnedSiteIds: Set<UUID> = []
    private var warnedGlobal: Bool = false

    private let sitesKey = "TimeWaster.Sites.v1"
    private let settingsKey = "TimeWaster.Settings.v1"
    private let usagePrefix = "TimeWaster.Usage.v1."

    let challengePhrase = "I am choosing to spend five more minutes here intentionally"

    private init() {
        let todayStr = Self.dateString(for: Date())
        self.todayRecord = DailyUsageRecord(dateString: todayStr)
        loadAll()
        startMonitoring()
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func dateStringDaysAgo(_ days: Int) -> String {
        let target = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return Self.dateString(for: target)
    }

    nonisolated static func extractHost(from rawURL: String?) -> String? {
        guard let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawURL.isEmpty,
              let url = URL(string: rawURL),
              var host = url.host?.lowercased() else {
            return nil
        }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    private func checkEndOfWeekSummaryPopup() {
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1 == Sunday in Gregorian calendar
        let hour = cal.component(.hour, from: now)

        // Trigger automatically on Sunday evening (6 PM or later) once per ISO week
        guard weekday == 1 && hour >= 18 else { return }

        let year = cal.component(.yearForWeekOfYear, from: now)
        let week = cal.component(.weekOfYear, from: now)
        let weekKey = "\(year)-W\(week)"

        if !UsageDatabase.shared.hasShownWeeklyReport(for: weekKey) {
            UsageDatabase.shared.markWeeklyReportShown(for: weekKey)
            NSSound.beep()
            WeeklyReportWindowController.shared.show()
        }
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        checkDateRollover()

        guard !settings.pauseTracking else {
            activeSite = nil
            return
        }

        guard let context = BrowserMonitor.shared.getCurrentContext() else {
            activeSite = nil
            return
        }

        lastDetectedURL = context.url

        // Ignore if the user is already viewing our local block page
        if let url = context.url, url.contains("TimeWasterBlock_") {
            activeSite = nil
            return
        }

        let matchedSite = matchSite(for: context)
        let isDistraction = (matchedSite?.isEnabled == true)
        let cleanDomain = Self.extractHost(from: context.url)

        // Log EVERY active app & website domain into the SQLite database
        UsageDatabase.shared.recordSecond(
            date: todayRecord.dateString,
            appName: context.appName,
            bundleId: context.bundleIdentifier,
            domain: cleanDomain,
            isDistraction: isDistraction
        )

        // Check if it's the end of the week (Sunday >= 6 PM) and pop up the weekly summary once per week
        checkEndOfWeekSummaryPopup()

        // Match either by URL domain or by native app bundle ID for capping
        guard let matchedSite = matchedSite, matchedSite.isEnabled else {
            activeSite = nil
            return
        }

        activeSite = matchedSite

        // Increment usage by 1 second
        let currentSeconds = todayRecord.secondsUsed(for: matchedSite.id) + 1
        todayRecord.secondsBySiteId[matchedSite.id] = currentSeconds
        saveTodayUsage()

        // Check if user has an active temporary bonus unlock
        if todayRecord.hasActiveBonus(for: matchedSite.id) {
            return
        }

        let siteExceeded = currentSeconds >= matchedSite.dailyLimitSeconds
        let globalExceeded = settings.useGlobalBudget && (todayRecord.totalSecondsUsed >= settings.globalDailyBudgetMinutes * 60)

        // Check warning threshold
        let warningSec = settings.warningMinutesBefore * 60
        if !warnedSiteIds.contains(matchedSite.id) && (matchedSite.dailyLimitSeconds - currentSeconds == warningSec) && warningSec > 0 {
            warnedSiteIds.insert(matchedSite.id)
            NSSound.beep()
        }
        if settings.useGlobalBudget && !warnedGlobal && (settings.globalDailyBudgetMinutes * 60 - todayRecord.totalSecondsUsed == warningSec) && warningSec > 0 {
            warnedGlobal = true
            NSSound.beep()
        }

        // Enforce cap if reached
        if siteExceeded || globalExceeded {
            let reason = siteExceeded
                ? "You hit your \(matchedSite.dailyLimitMinutes) min daily cap on \(matchedSite.name)."
                : "You hit your \(settings.globalDailyBudgetMinutes) min combined daily budget."

            let blockURL = BlockPageGenerator.writeBlockPage(
                site: matchedSite,
                usedSeconds: currentSeconds,
                totalSeconds: todayRecord.totalSecondsUsed,
                reason: reason,
                strictness: settings.strictness
            )
            BrowserMonitor.shared.enforceBlock(context: context, blockPageURL: blockURL)
            BlockOverlayWindowController.shared.show(site: matchedSite, reason: reason)
        }
    }

    private func matchSite(for context: ActiveContext) -> TrackedSite? {
        for site in sites {
            if site.blockAppBundleIds.contains(context.bundleIdentifier) {
                return site
            }
            if let rawURL = context.url?.lowercased(),
               let urlObj = URL(string: rawURL),
               let host = urlObj.host?.lowercased() {
                for domain in site.domains {
                    let cleanDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if host == cleanDomain || host.hasSuffix("." + cleanDomain) {
                        return site
                    }
                }
            }
        }
        return nil
    }

    func grantFiveMinuteBonus(for siteId: UUID) {
        todayRecord.bonusUntilBySiteId[siteId] = Date().addingTimeInterval(5 * 60)
        saveTodayUsage()
        BlockOverlayWindowController.shared.close()
    }

    func resetSiteUsage(_ siteId: UUID) {
        todayRecord.secondsBySiteId[siteId] = 0
        todayRecord.bonusUntilBySiteId.removeValue(forKey: siteId)
        warnedSiteIds.remove(siteId)
        saveTodayUsage()
    }

    func addCustomSite(name: String, domainString: String, limitMinutes: Int) {
        let domains = domainString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !name.isEmpty, !domains.isEmpty else { return }

        let newSite = TrackedSite(
            name: name,
            domains: domains,
            dailyLimitMinutes: max(1, limitMinutes),
            iconName: "globe",
            colorHex: "#F59E0B"
        )
        sites.append(newSite)
    }

    func removeSite(at offsets: IndexSet) {
        sites.remove(atOffsets: offsets)
    }

    var menuBarLabel: String {
        if settings.pauseTracking {
            return "⏸"
        }
        if let active = activeSite {
            let used = todayRecord.secondsUsed(for: active.id)
            let remaining = max(0, active.dailyLimitSeconds - used)
            return Self.formatCompactMenuBarTime(remaining)
        }
        if settings.useGlobalBudget {
            let remaining = max(0, settings.globalDailyBudgetMinutes * 60 - todayRecord.totalSecondsUsed)
            return Self.formatCompactMenuBarTime(remaining)
        }
        return Self.formatCompactMenuBarTime(todayRecord.totalSecondsUsed)
    }

    nonisolated static func formatCompactMenuBarTime(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remMins = mins % 60
            return String(format: "%dh%02dm", hrs, remMins)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    nonisolated static func formatShortTime(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remMins = mins % 60
            return String(format: "%dh %02dm", hrs, remMins)
        }
        return String(format: "%dm %02ds", mins, secs)
    }

    private func checkDateRollover() {
        let currentStr = Self.dateString(for: Date())
        if todayRecord.dateString != currentStr {
            todayRecord = loadUsage(for: currentStr)
            warnedSiteIds.removeAll()
            warnedGlobal = false
        }
    }

    private func loadAll() {
        if let data = UserDefaults.standard.data(forKey: sitesKey),
           let decoded = try? JSONDecoder().decode([TrackedSite].self, from: data) {
            self.sites = decoded
        } else {
            self.sites = TrackedSite.defaults
        }

        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        }

        let todayStr = Self.dateString(for: Date())
        self.todayRecord = loadUsage(for: todayStr)
    }

    private func loadUsage(for dateStr: String) -> DailyUsageRecord {
        if let data = UserDefaults.standard.data(forKey: usagePrefix + dateStr),
           let decoded = try? JSONDecoder().decode(DailyUsageRecord.self, from: data) {
            return decoded
        }
        return DailyUsageRecord(dateString: dateStr)
    }

    private func saveSites() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: sitesKey)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func saveTodayUsage() {
        if let data = try? JSONEncoder().encode(todayRecord) {
            UserDefaults.standard.set(data, forKey: usagePrefix + todayRecord.dateString)
        }
    }
}
