import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @ObservedObject var manager = TimeTrackerManager.shared
    @State private var selectedTab: Int = 0
    @State private var newSiteName: String = ""
    @State private var newSiteDomain: String = ""
    @State private var newSiteMinutes: Int = 20

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            Picker("", selection: $selectedTab) {
                Text("Today").tag(0)
                Text("Analytics").tag(1)
                Text("Limits").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                if selectedTab == 0 {
                    todayUsageTab
                } else if selectedTab == 1 {
                    analyticsTab
                } else if selectedTab == 2 {
                    limitsConfigTab
                } else {
                    settingsTab
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
            footerSection
        }
        .frame(width: 370)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(manager.activeSite != nil ? Color.red.opacity(0.18) : Color.blue.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: manager.activeSite != nil ? "flame.fill" : "hourglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(manager.activeSite != nil ? .red : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("TimeWaster Cap")
                        .font(.headline)
                    if let active = manager.activeSite {
                        Text("LIVE: \(active.name)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                Text(globalSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var globalSummaryText: String {
        let totalUsed = TimeTrackerManager.formatShortTime(manager.todayRecord.totalSecondsUsed)
        if manager.settings.useGlobalBudget {
            return "Today: \(totalUsed) / \(manager.settings.globalDailyBudgetMinutes)m daily budget"
        }
        return "Total tracked today: \(totalUsed)"
    }

    private var todayUsageTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if manager.settings.useGlobalBudget {
                    globalBudgetCard
                }

                ForEach(manager.sites.filter { $0.isEnabled }) { site in
                    SiteUsageRow(site: site, usedSeconds: manager.todayRecord.secondsUsed(for: site.id))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 320)
    }

    private var analyticsTab: some View {
        let sevenDaysAgo = manager.dateStringDaysAgo(6)
        let topDomains = UsageDatabase.shared.topDomains(sinceDate: sevenDaysAgo, limit: 6)
        let topApps = UsageDatabase.shared.topApps(sinceDate: sevenDaysAgo, limit: 6)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("7-Day Activity Log (SQLite)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Full Report") {
                        WeeklyReportWindowController.shared.show()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Websites (All Browsing)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    if topDomains.isEmpty {
                        Text("No domains logged yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topDomains) { row in
                            HStack {
                                Circle()
                                    .fill(row.isDistraction ? Color.red : Color.blue)
                                    .frame(width: 6, height: 6)
                                Text(row.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(TimeTrackerManager.formatShortTime(row.seconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Mac Applications")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    ForEach(topApps) { row in
                        HStack {
                            Text(row.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(TimeTrackerManager.formatShortTime(row.seconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 320)
    }

    private var globalBudgetCard: some View {
        let usedSec = manager.todayRecord.totalSecondsUsed
        let capSec = max(1, manager.settings.globalDailyBudgetMinutes * 60)
        let ratio = min(1.0, Double(usedSec) / Double(capSec))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Combined Streaming & Social Pool", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(TimeTrackerManager.formatShortTime(usedSec)) / \(manager.settings.globalDailyBudgetMinutes)m")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }

            ProgressView(value: ratio)
                .tint(ratio >= 0.9 ? .red : (ratio >= 0.7 ? .orange : .blue))
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var limitsConfigTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($manager.sites) { $site in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $site.isEnabled)
                            .labelsHidden()
                            .controlSize(.small)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name)
                                .font(.subheadline.weight(.medium))
                            Text(site.domains.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Stepper(value: $site.dailyLimitMinutes, in: 1...360, step: 5) {
                            Text("\(site.dailyLimitMinutes)m")
                                .font(.caption.monospacedDigit().bold())
                                .frame(width: 38, alignment: .trailing)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Custom Site")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        TextField("Name (e.g. Twitch)", text: $newSiteName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                        TextField("Domain (twitch.tv)", text: $newSiteDomain)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }

                    HStack {
                        Stepper("Cap: \(newSiteMinutes)m", value: $newSiteMinutes, in: 5...240, step: 5)
                            .font(.caption)
                        Spacer()
                        Button("Add Site") {
                            manager.addCustomSite(
                                name: newSiteName,
                                domainString: newSiteDomain,
                                limitMinutes: newSiteMinutes
                            )
                            newSiteName = ""
                            newSiteDomain = ""
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(newSiteName.isEmpty || newSiteDomain.isEmpty)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 320)
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enforce combined daily budget", isOn: $manager.settings.useGlobalBudget)
                .font(.subheadline)

            if manager.settings.useGlobalBudget {
                HStack {
                    Text("Total Daily Cap:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(
                        "\(manager.settings.globalDailyBudgetMinutes) min / day",
                        value: $manager.settings.globalDailyBudgetMinutes,
                        in: 10...480,
                        step: 10
                    )
                    .font(.caption.monospacedDigit())
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("When a Time Limit is Reached:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Picker("", selection: $manager.settings.strictness) {
                    ForEach(StrictnessMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .font(.caption)
            }

            Divider()

            Toggle("Pause tracking temporarily", isOn: $manager.settings.pauseTracking)
                .font(.subheadline)

            if let url = manager.lastDetectedURL, !url.isEmpty {
                Text("Active URL: \(url)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(16)
        .frame(height: 320)
    }

    private var footerSection: some View {
        HStack(spacing: 12) {
            Button {
                if let site = manager.sites.first {
                    let reason = "Previewing how TimeWaster blocks \(site.name) when your cap hits."
                    BlockOverlayWindowController.shared.show(site: site, reason: reason)
                }
            } label: {
                Label("Test Block", systemImage: "shield.lefthalf.filled")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                WeeklyReportWindowController.shared.show()
            } label: {
                Label("Weekly Report", systemImage: "chart.bar.doc.horizontal")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct SiteUsageRow: View {
    let site: TrackedSite
    let usedSeconds: Int
    @ObservedObject private var manager = TimeTrackerManager.shared

    var body: some View {
        let capSeconds = max(1, site.dailyLimitSeconds)
        let ratio = min(1.0, Double(usedSeconds) / Double(capSeconds))
        let isBlocked = usedSeconds >= capSeconds && !manager.todayRecord.hasActiveBonus(for: site.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: site.iconName)
                    .foregroundStyle(isBlocked ? .red : .primary)
                    .frame(width: 18)

                Text(site.name)
                    .font(.subheadline.weight(.medium))

                if isBlocked {
                    Text("CAPPED")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.2))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                } else if manager.todayRecord.hasActiveBonus(for: site.id) {
                    Text("+5m UNLOCKED")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Spacer()

                Text("\(TimeTrackerManager.formatShortTime(usedSeconds)) / \(site.dailyLimitMinutes)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isBlocked ? .red : .secondary)
            }

            ProgressView(value: ratio)
                .tint(isBlocked ? .red : (ratio >= 0.8 ? .orange : .accentColor))
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Reset Today's Counter for \(site.name)") {
                manager.resetSiteUsage(site.id)
            }
        }
    }
}
