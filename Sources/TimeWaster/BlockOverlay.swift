import Foundation
import SwiftUI
import AppKit

enum BlockPageGenerator {
    static func writeBlockPage(
        site: TrackedSite,
        usedSeconds: Int,
        totalSeconds: Int,
        reason: String,
        strictness: StrictnessMode
    ) -> String {
        let usedFormatted = TimeTrackerManager.formatShortTime(usedSeconds)
        let totalFormatted = TimeTrackerManager.formatShortTime(totalSeconds)

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Time Cap Reached — \(site.name)</title>
            <style>
                :root {
                    color-scheme: dark;
                }
                * {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
                    background: radial-gradient(circle at top, #1e1b4b 0%, #09090b 70%);
                    color: #f8fafc;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 24px;
                }
                .card {
                    max-width: 540px;
                    width: 100%;
                    background: rgba(24, 24, 27, 0.85);
                    border: 1px solid rgba(255, 255, 255, 0.12);
                    border-radius: 24px;
                    padding: 40px;
                    text-align: center;
                    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7);
                    backdrop-filter: blur(16px);
                }
                .badge {
                    display: inline-block;
                    padding: 6px 14px;
                    border-radius: 999px;
                    background: rgba(239, 68, 68, 0.18);
                    color: #f87171;
                    border: 1px solid rgba(239, 68, 68, 0.35);
                    font-size: 13px;
                    font-weight: 600;
                    letter-spacing: 0.04em;
                    text-transform: uppercase;
                    margin-bottom: 20px;
                }
                h1 {
                    font-size: 32px;
                    font-weight: 700;
                    letter-spacing: -0.02em;
                    margin-bottom: 12px;
                }
                p.subtitle {
                    color: #94a3b8;
                    font-size: 16px;
                    line-height: 1.5;
                    margin-bottom: 28px;
                }
                .stats {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 16px;
                    margin-bottom: 28px;
                }
                .stat-box {
                    background: rgba(255, 255, 255, 0.04);
                    border: 1px solid rgba(255, 255, 255, 0.08);
                    border-radius: 16px;
                    padding: 16px;
                }
                .stat-value {
                    font-size: 24px;
                    font-weight: 700;
                    color: #e2e8f0;
                    margin-bottom: 4px;
                }
                .stat-label {
                    font-size: 12px;
                    color: #64748b;
                    text-transform: uppercase;
                    letter-spacing: 0.05em;
                }
                .hint {
                    font-size: 13px;
                    color: #64748b;
                    border-top: 1px solid rgba(255, 255, 255, 0.08);
                    padding-top: 20px;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="badge">Daily Limit Reached</div>
                <h1>Time's up for \(site.name)</h1>
                <p class="subtitle">\(reason)</p>
                <div class="stats">
                    <div class="stat-box">
                        <div class="stat-value">\(usedFormatted)</div>
                        <div class="stat-label">Spent on \(site.name)</div>
                    </div>
                    <div class="stat-box">
                        <div class="stat-value">\(totalFormatted)</div>
                        <div class="stat-label">Total Tracked Today</div>
                    </div>
                </div>
                <div class="hint">
                    \(strictness == .friction ? "Need 5 emergency minutes? Use the TimeWaster pop-up window or menu bar icon." : "Strict lockout is active until midnight.")
                </div>
            </div>
        </body>
        </html>
        """

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("TimeWasterBlock_\(site.id.uuidString).html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.absoluteString
    }
}

@MainActor
final class BlockOverlayWindowController {
    static let shared = BlockOverlayWindowController()
    private var window: NSWindow?

    func show(site: TrackedSite, reason: String) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = BlockModalView(site: site, reason: reason) { [weak self] in
            self?.close()
        }

        let hosting = NSHostingController(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
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

struct BlockModalView: View {
    let site: TrackedSite
    let reason: String
    let onClose: () -> Void

    @ObservedObject private var manager = TimeTrackerManager.shared
    @State private var typedPhrase: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 42))
                .foregroundStyle(.red)
                .padding(.top, 8)

            Text("Time Cap Reached: \(site.name)")
                .font(.title2.bold())

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if manager.settings.strictness == .friction {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To unlock 5 extra minutes, type the exact phrase below:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(manager.challengePhrase)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    TextField("Type phrase here...", text: $typedPhrase)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
            } else {
                Text("Hard Lockout mode is enabled. This site is locked until midnight.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
            }

            HStack(spacing: 12) {
                Button("Back to Work") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

                if manager.settings.strictness == .friction {
                    Button("Unlock +5m") {
                        manager.grantFiveMinuteBonus(for: site.id)
                    }
                    .disabled(typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines) != manager.challengePhrase)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(width: 460)
    }
}
