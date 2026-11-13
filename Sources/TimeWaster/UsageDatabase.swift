import Foundation
import SQLite3

struct UsageStatRow: Identifiable {
    var id: String { name }
    let name: String
    let secondaryLabel: String?
    let seconds: Int
    let isDistraction: Bool
}

struct DailyTotalRow: Identifiable {
    var id: String { dateString }
    let dateString: String
    let totalSeconds: Int
    let distractionSeconds: Int
}

final class UsageDatabase {
    static let shared = UsageDatabase()

    let dbPath: String
    private var db: OpaquePointer?

    private init() {
        // Resolve the directory containing TimeWaster.app (or current working directory) dynamically
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent().path
        let baseDir = bundleParent.isEmpty ? FileManager.default.currentDirectoryPath : bundleParent
        let dataDir = (baseDir as NSString).appendingPathComponent("data")
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        self.dbPath = (dataDir as NSString).appendingPathComponent("timewaster.sqlite")
        openAndMigrate()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func openAndMigrate() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open SQLite database at \(dbPath)")
            return
        }

        let createSQL = """
        PRAGMA journal_mode = WAL;

        CREATE TABLE IF NOT EXISTS daily_app_usage (
            date TEXT NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            seconds INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, bundle_id)
        );

        CREATE TABLE IF NOT EXISTS daily_domain_usage (
            date TEXT NOT NULL,
            domain TEXT NOT NULL,
            app_name TEXT NOT NULL,
            is_distraction INTEGER NOT NULL DEFAULT 0,
            seconds INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, domain)
        );

        CREATE TABLE IF NOT EXISTS weekly_reports_shown (
            week_key TEXT PRIMARY KEY,
            shown_at TEXT NOT NULL
        );
        """
        executeRaw(createSQL)
    }

    func recordSecond(
        date: String,
        appName: String,
        bundleId: String,
        domain: String?,
        isDistraction: Bool
    ) {
        let appUpsert = """
        INSERT INTO daily_app_usage (date, app_name, bundle_id, seconds)
        VALUES (?, ?, ?, 1)
        ON CONFLICT(date, bundle_id) DO UPDATE SET
            seconds = seconds + 1,
            app_name = excluded.app_name;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, appUpsert, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: date)
            bindText(stmt, index: 2, value: appName)
            bindText(stmt, index: 3, value: bundleId)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        if let domain = domain, !domain.isEmpty {
            let domainUpsert = """
            INSERT INTO daily_domain_usage (date, domain, app_name, is_distraction, seconds)
            VALUES (?, ?, ?, ?, 1)
            ON CONFLICT(date, domain) DO UPDATE SET
                seconds = seconds + 1,
                is_distraction = excluded.is_distraction;
            """
            var domStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, domainUpsert, -1, &domStmt, nil) == SQLITE_OK {
                bindText(domStmt, index: 1, value: date)
                bindText(domStmt, index: 2, value: domain)
                bindText(domStmt, index: 3, value: appName)
                sqlite3_bind_int(domStmt, 4, isDistraction ? 1 : 0)
                sqlite3_step(domStmt)
            }
            sqlite3_finalize(domStmt)
        }
    }

    func topDomains(sinceDate: String, limit: Int = 10) -> [UsageStatRow] {
        let sql = """
        SELECT domain, app_name, SUM(seconds) as total_sec, MAX(is_distraction)
        FROM daily_domain_usage
        WHERE date >= ?
        GROUP BY domain
        ORDER BY total_sec DESC
        LIMIT ?;
        """
        var rows: [UsageStatRow] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: sinceDate)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let domain = columnString(stmt, index: 0)
                let app = columnString(stmt, index: 1)
                let secs = Int(sqlite3_column_int(stmt, 2))
                let isDist = sqlite3_column_int(stmt, 3) == 1
                rows.append(UsageStatRow(name: domain, secondaryLabel: app, seconds: secs, isDistraction: isDist))
            }
        }
        sqlite3_finalize(stmt)
        return rows
    }

    func topApps(sinceDate: String, limit: Int = 10) -> [UsageStatRow] {
        let sql = """
        SELECT app_name, bundle_id, SUM(seconds) as total_sec
        FROM daily_app_usage
        WHERE date >= ?
        GROUP BY bundle_id
        ORDER BY total_sec DESC
        LIMIT ?;
        """
        var rows: [UsageStatRow] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: sinceDate)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let app = columnString(stmt, index: 0)
                let bundle = columnString(stmt, index: 1)
                let secs = Int(sqlite3_column_int(stmt, 2))
                rows.append(UsageStatRow(name: app, secondaryLabel: bundle, seconds: secs, isDistraction: false))
            }
        }
        sqlite3_finalize(stmt)
        return rows
    }

    func dailyBreakdown(sinceDate: String) -> [DailyTotalRow] {
        let sql = """
        SELECT a.date,
               SUM(a.seconds) as total_app_sec,
               COALESCE((SELECT SUM(d.seconds) FROM daily_domain_usage d WHERE d.date = a.date AND d.is_distraction = 1), 0) as dist_sec
        FROM daily_app_usage a
        WHERE a.date >= ?
        GROUP BY a.date
        ORDER BY a.date DESC;
        """
        var rows: [DailyTotalRow] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: sinceDate)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let d = columnString(stmt, index: 0)
                let total = Int(sqlite3_column_int(stmt, 1))
                let dist = Int(sqlite3_column_int(stmt, 2))
                rows.append(DailyTotalRow(dateString: d, totalSeconds: total, distractionSeconds: dist))
            }
        }
        sqlite3_finalize(stmt)
        return rows
    }

    func hasShownWeeklyReport(for weekKey: String) -> Bool {
        let sql = "SELECT 1 FROM weekly_reports_shown WHERE week_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: weekKey)
            if sqlite3_step(stmt) == SQLITE_ROW {
                exists = true
            }
        }
        sqlite3_finalize(stmt)
        return exists
    }

    func markWeeklyReportShown(for weekKey: String) {
        let sql = "INSERT OR REPLACE INTO weekly_reports_shown (week_key, shown_at) VALUES (?, datetime('now'));"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: weekKey)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func executeRaw(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQLite error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func columnString(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }
}
