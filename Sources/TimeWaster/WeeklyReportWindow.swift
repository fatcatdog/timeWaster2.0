import SwiftUI
import AppKit

@MainActor
final class WeeklyReportWindowController {
    static let shared = WeeklyReportWindowController()
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = WeeklyReportModalView { [weak self] in
            self?.close()
        }

        let hosting = NSHostingController(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.center()
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct WeeklyReportModalView: View {
    let onClose: () -> Void
    @ObservedObject private var manager = TimeTrackerManager.shared

    var body: some View {
        let sevenDaysAgo = manager.dateStringDaysAgo(6)
        let topDomains = UsageDatabase.shared.topDomains(sinceDate: sevenDaysAgo, limit: 8)
        let topApps = UsageDatabase.shared.topApps(sinceDate: sevenDaysAgo, limit: 8)
        let dailyRows = UsageDatabase.shared.dailyBreakdown(sinceDate: sevenDaysAgo)

        let totalScreenSec = dailyRows.reduce(0) { $0 + $1.totalSeconds }
        let totalDistractionSec = dailyRows.reduce(0) { $0 + $1.distractionSeconds }

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your 7-Day TimeWaster Summary")
                        .font(.title2.bold())
                    Text("Activity logged in SQLite over the last 7 days (since \(sevenDaysAgo))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                summaryStatBox(
                    title: "Total Active Mac Time",
                    value: TimeTrackerManager.formatShortTime(totalScreenSec),
                    color: .blue
                )
                summaryStatBox(
                    title: "Capped Sites Time",
                    value: TimeTrackerManager.formatShortTime(totalDistractionSec),
                    color: .red
                )
                let pct = totalScreenSec > 0 ? Int((Double(totalDistractionSec) / Double(totalScreenSec)) * 100) : 0
                summaryStatBox(
                    title: "Distraction Ratio",
                    value: "\(pct)%",
                    color: pct > 30 ? .orange : .green
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top Websites Visited (7 Days)")
                            .font(.subheadline.bold())

                        if topDomains.isEmpty {
                            Text("No website visits recorded yet. Browse in Safari/Chrome/Brave to populate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(topDomains) { row in
                                HStack {
                                    Circle()
                                        .fill(row.isDistraction ? Color.red : Color.blue)
                                        .frame(width: 7, height: 7)
                                    Text(row.name)
                                        .font(.system(.caption, design: .monospaced).weight(.medium))
                                    if row.isDistraction {
                                        Text("CAPPED SITE")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundStyle(.red)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(TimeTrackerManager.formatShortTime(row.seconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top Mac Applications (7 Days)")
                            .font(.subheadline.bold())

                        ForEach(topApps) { row in
                            HStack {
                                Image(systemName: "app.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(row.name)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text(TimeTrackerManager.formatShortTime(row.seconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            HStack {
                Text("DB: data/timewaster.sqlite")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540, height: 500)
    }

    private func summaryStatBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
