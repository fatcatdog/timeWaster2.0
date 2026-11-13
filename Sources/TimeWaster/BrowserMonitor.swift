import Foundation
import AppKit

struct ActiveContext {
    let appName: String
    let bundleIdentifier: String
    let url: String?
    let windowTitle: String?
}

final class BrowserMonitor {
    static let shared = BrowserMonitor()

    private let chromiumBrowsers: Set<String> = [
        "Google Chrome",
        "Brave Browser",
        "Arc",
        "Microsoft Edge",
        "Vivaldi",
        "Opera"
    ]

    /// Queries the frontmost macOS application and, if it is a supported browser, fetches the active tab URL.
    func getCurrentContext() -> ActiveContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName,
              let bundleId = frontApp.bundleIdentifier else {
            return nil
        }

        if appName == "Safari" || bundleId == "com.apple.Safari" {
            let info = runSafariScript()
            return ActiveContext(appName: appName, bundleIdentifier: bundleId, url: info.url, windowTitle: info.title)
        } else if chromiumBrowsers.contains(appName) {
            let info = runChromiumScript(appName: appName)
            return ActiveContext(appName: appName, bundleIdentifier: bundleId, url: info.url, windowTitle: info.title)
        } else {
            return ActiveContext(appName: appName, bundleIdentifier: bundleId, url: nil, windowTitle: nil)
        }
    }

    /// Redirects the active browser tab to the local block page URL, or hides/terminates native streaming apps.
    func enforceBlock(context: ActiveContext, blockPageURL: String) {
        if context.appName == "Safari" || context.bundleIdentifier == "com.apple.Safari" {
            let script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    set URL of current tab of front window to "\(blockPageURL)"
                end if
            end tell
            """
            _ = executeAppleScript(script)
        } else if chromiumBrowsers.contains(context.appName) {
            let script = """
            tell application "\(context.appName)"
                if (count of windows) > 0 then
                    set URL of active tab of front window to "\(blockPageURL)"
                end if
            end tell
            """
            _ = executeAppleScript(script)
        } else {
            // Native app (e.g., Prime Video.app) — hide it and open the block page in the default browser
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier).first {
                app.hide()
            }
            if let url = URL(string: blockPageURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func runSafariScript() -> (url: String?, title: String?) {
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                set currentTab to current tab of front window
                return (URL of currentTab) & "|||" & (name of currentTab)
            end if
        end tell
        """
        return parseScriptOutput(executeAppleScript(script))
    }

    private func runChromiumScript(appName: String) -> (url: String?, title: String?) {
        let script = """
        tell application "\(appName)"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                return (URL of activeTab) & "|||" & (title of activeTab)
            end if
        end tell
        """
        return parseScriptOutput(executeAppleScript(script))
    }

    private func parseScriptOutput(_ raw: String?) -> (url: String?, title: String?) {
        guard let raw = raw, !raw.isEmpty else { return (nil, nil) }
        let parts = raw.components(separatedBy: "|||")
        let url = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (url, title)
    }

    private func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: source) else { return nil }
        let descriptor = scriptObject.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        return descriptor.stringValue
    }
}
