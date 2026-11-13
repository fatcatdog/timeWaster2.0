import SwiftUI
import AppKit

@main
struct TimeWasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var manager = TimeTrackerManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: manager.activeSite != nil ? "flame.fill" : "hourglass")
                Text(manager.menuBarLabel)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a clean macOS Menu Bar agent (no clutter in the Dock)
        NSApp.setActivationPolicy(.accessory)
    }
}
