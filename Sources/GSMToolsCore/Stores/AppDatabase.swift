import Foundation
import GRDB

public struct RawTelemetryEntry: Equatable, Sendable {
    public var runId: UUID
    public var imei: String
    public var endpoint: String
    public var recordCount: Int
    public var byteCount: Int64
    public var payload: Data
    public var storedAt: Date
}

public enum AppDatabaseError: Error, LocalizedError, Equatable {
    case invalidStoredRunId(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidStoredRunId(runId):
            return "Database row contains an invalid run id: \(runId)."
        }
    }
}

public final class AppDatabase {
    public let dbQueue: DatabaseQueue

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        self.encoder = JSONEncoder.persistence
        self.decoder = JSONDecoder.persistence
        try Self.migrator.migrate(dbQueue)
    }

    public static func applicationSupportDatabase() throws -> AppDatabase {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("GSMTools", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try AppDatabase(path: directory.appendingPathComponent("gsmtools.sqlite").path)
    }

    public func saveRun(_ run: AnalysisRun) throws {
        let payload = try encoder.encode(run)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO analysis_runs (id, name, state, updated_at, payload)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  state = excluded.state,
                  updated_at = excluded.updated_at,
                  payload = excluded.payload
                """,
                arguments: [
                    run.id.uuidString,
                    run.name,
                    run.state.rawValue,
                    run.updatedAt.timeIntervalSince1970,
                    payload
                ]
            )
        }
    }

    public func fetchRuns() throws -> [AnalysisRun] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM analysis_runs ORDER BY updated_at DESC")
            return try rows.map { row in
                try decoder.decode(AnalysisRun.self, from: row["payload"])
            }
        }
    }

    public func deleteRun(id: UUID) throws {
        try dbQueue.write { db in
            let runId = id.uuidString
            try db.execute(sql: "DELETE FROM raw_cache_entries WHERE run_id = ?", arguments: [runId])
            try db.execute(sql: "DELETE FROM raw_telemetry WHERE run_id = ?", arguments: [runId])
            try db.execute(sql: "DELETE FROM reports WHERE run_id = ?", arguments: [runId])
            try db.execute(sql: "DELETE FROM alert_flags WHERE run_id = ?", arguments: [runId])
            try db.execute(sql: "DELETE FROM analysis_runs WHERE id = ?", arguments: [runId])
        }
    }

    public func saveTestGroup(_ group: TestGroup) throws {
        let payload = try encoder.encode(group)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO test_groups (id, name, updated_at, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  updated_at = excluded.updated_at,
                  payload = excluded.payload
                """,
                arguments: [
                    group.id.uuidString,
                    group.name,
                    group.updatedAt.timeIntervalSince1970,
                    payload
                ]
            )
        }
    }

    public func fetchTestGroups() throws -> [TestGroup] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM test_groups ORDER BY updated_at DESC")
            return try rows.map { row in
                try decoder.decode(TestGroup.self, from: row["payload"])
            }
        }
    }

    public func deleteTestGroup(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM test_groups WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func saveReport(_ report: Report) throws {
        let payload = try encoder.encode(report)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO reports (id, run_id, title, generated_at, payload)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  run_id = excluded.run_id,
                  title = excluded.title,
                  generated_at = excluded.generated_at,
                  payload = excluded.payload
                """,
                arguments: [
                    report.id.uuidString,
                    report.runId?.uuidString,
                    report.title,
                    report.generatedAt.timeIntervalSince1970,
                    payload
                ]
            )
        }
    }

    public func fetchReports() throws -> [Report] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM reports ORDER BY generated_at DESC")
            return try rows.map { row in
                try decoder.decode(Report.self, from: row["payload"])
            }
        }
    }

    public func saveAlert(_ flag: AlertFlag) throws {
        let payload = try encoder.encode(flag)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO alert_flags (id, run_id, imei, severity, created_at, payload)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  run_id = excluded.run_id,
                  imei = excluded.imei,
                  severity = excluded.severity,
                  created_at = excluded.created_at,
                  payload = excluded.payload
                """,
                arguments: [
                    flag.id.uuidString,
                    flag.runId?.uuidString,
                    flag.imei,
                    flag.severity.rawValue,
                    flag.createdAt.timeIntervalSince1970,
                    payload
                ]
            )
        }
    }

    public func fetchAlerts() throws -> [AlertFlag] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM alert_flags ORDER BY created_at DESC")
            return try rows.map { row in
                try decoder.decode(AlertFlag.self, from: row["payload"])
            }
        }
    }

    public func recordRawCacheEntry(runId: UUID, imei: String, endpoint: String, recordCount: Int, byteCount: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO raw_cache_entries (run_id, imei, endpoint, record_count, byte_count, stored_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    runId.uuidString,
                    imei,
                    endpoint,
                    recordCount,
                    byteCount,
                    Date().timeIntervalSince1970
                ]
            )
        }
    }

    public func saveRawTelemetry(runId: UUID, bundles: [TelemetryBundle]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM raw_telemetry WHERE run_id = ?", arguments: [runId.uuidString])
            for bundle in bundles {
                try insertRawTelemetry(runId: runId, imei: bundle.imei, endpoint: "locations", records: bundle.locations, db: db)
                try insertRawTelemetry(runId: runId, imei: bundle.imei, endpoint: "sensors", records: bundle.sensors, db: db)
                try insertRawTelemetry(runId: runId, imei: bundle.imei, endpoint: "connections", records: bundle.connections, db: db)
                try insertRawTelemetry(runId: runId, imei: bundle.imei, endpoint: "instructions", records: bundle.instructions, db: db)
            }
        }
    }

    public func fetchRawTelemetryEntries(runId: UUID) throws -> [RawTelemetryEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT run_id, imei, endpoint, record_count, byte_count, payload, stored_at
                FROM raw_telemetry
                WHERE run_id = ?
                ORDER BY imei, endpoint
                """,
                arguments: [runId.uuidString]
            )
            return try rows.map { row in
                let runIdString: String = row["run_id"]
                guard let id = UUID(uuidString: runIdString) else {
                    throw AppDatabaseError.invalidStoredRunId(runIdString)
                }
                return RawTelemetryEntry(
                    runId: id,
                    imei: row["imei"],
                    endpoint: row["endpoint"],
                    recordCount: row["record_count"],
                    byteCount: row["byte_count"],
                    payload: row["payload"],
                    storedAt: Date(timeIntervalSince1970: row["stored_at"])
                )
            }
        }
    }

    public func rawCacheBytes() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byte_count), 0) FROM raw_cache_entries") ?? 0
        }
    }

    private func insertRawTelemetry<Record: Encodable>(
        runId: UUID,
        imei: String,
        endpoint: String,
        records: [Record],
        db: Database
    ) throws {
        let payload = try encoder.encode(records)
        try db.execute(
            sql: """
            INSERT INTO raw_telemetry (run_id, imei, endpoint, record_count, byte_count, payload, stored_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(run_id, imei, endpoint) DO UPDATE SET
              record_count = excluded.record_count,
              byte_count = excluded.byte_count,
              payload = excluded.payload,
              stored_at = excluded.stored_at
            """,
            arguments: [
                runId.uuidString,
                imei,
                endpoint,
                records.count,
                Int64(payload.count),
                payload,
                Date().timeIntervalSince1970
            ]
        )
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "analysis_runs", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("state", .text).notNull()
                table.column("updated_at", .double).notNull()
                table.column("payload", .blob).notNull()
            }

            try db.create(table: "reports", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("run_id", .text)
                table.column("title", .text).notNull()
                table.column("generated_at", .double).notNull()
                table.column("payload", .blob).notNull()
            }

            try db.create(table: "alert_flags", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("run_id", .text)
                table.column("imei", .text)
                table.column("severity", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("payload", .blob).notNull()
            }

            try db.create(table: "raw_cache_entries", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("run_id", .text).notNull()
                table.column("imei", .text).notNull()
                table.column("endpoint", .text).notNull()
                table.column("record_count", .integer).notNull()
                table.column("byte_count", .integer).notNull()
                table.column("stored_at", .double).notNull()
            }

            try db.create(index: "idx_analysis_runs_updated_at", on: "analysis_runs", columns: ["updated_at"], ifNotExists: true)
            try db.create(index: "idx_reports_generated_at", on: "reports", columns: ["generated_at"], ifNotExists: true)
            try db.create(index: "idx_alert_flags_created_at", on: "alert_flags", columns: ["created_at"], ifNotExists: true)
        }

        migrator.registerMigration("v2_test_groups") { db in
            try db.create(table: "test_groups", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("updated_at", .double).notNull()
                table.column("payload", .blob).notNull()
            }

            try db.create(index: "idx_test_groups_updated_at", on: "test_groups", columns: ["updated_at"], ifNotExists: true)
        }

        migrator.registerMigration("v3_raw_telemetry") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS raw_telemetry (
              run_id TEXT NOT NULL,
              imei TEXT NOT NULL,
              endpoint TEXT NOT NULL,
              record_count INTEGER NOT NULL,
              byte_count INTEGER NOT NULL,
              payload BLOB NOT NULL,
              stored_at DOUBLE NOT NULL,
              PRIMARY KEY (run_id, imei, endpoint)
            )
            """)

            try db.create(index: "idx_raw_telemetry_run_id", on: "raw_telemetry", columns: ["run_id"], ifNotExists: true)
        }

        return migrator
    }
}

extension JSONEncoder {
    static var persistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var persistence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
