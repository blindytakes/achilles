// PhotoIndexStore.swift
//
// Incremental, transactional persistence for the on-device photo index.
// Each asset is stored independently so a small PhotoKit change does not
// rewrite the user's complete library snapshot.

import Foundation
import SQLite3

final class PhotoIndexStore: @unchecked Sendable {
    enum StoreError: LocalizedError {
        case open(String)
        case execute(String)
        case prepare(String)
        case bind(String)
        case step(String)

        var errorDescription: String? {
            switch self {
            case .open(let message): return "Could not open photo index: \(message)"
            case .execute(let message): return "Photo index command failed: \(message)"
            case .prepare(let message): return "Could not prepare photo index command: \(message)"
            case .bind(let message): return "Could not bind photo index value: \(message)"
            case .step(let message): return "Photo index write failed: \(message)"
            }
        }
    }

    private let databaseURL: URL
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadEntries() throws -> [String: IndexEntry] {
        try openIfNeeded()
        let sql = "SELECT asset_id, payload FROM photo_entries;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var entries: [String: IndexEntry] = [:]
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let byteCount = Int(sqlite3_column_bytes(statement, 1))
            if let identifierText = sqlite3_column_text(statement, 0),
               byteCount > 0,
               let bytes = sqlite3_column_blob(statement, 1) {
                let identifier = String(cString: identifierText)
                let data = Data(bytes: bytes, count: byteCount)
                if let entry = try? decoder.decode(IndexEntry.self, from: data) {
                    entries[identifier] = entry
                }
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw StoreError.step(lastErrorMessage)
        }
        return entries
    }

    func replaceAll(with entries: [String: IndexEntry], schemaVersion: Int) throws {
        do {
            try replaceAllOnce(with: entries, schemaVersion: schemaVersion)
        } catch {
            // The index is derived data. Preserve a broken database for
            // diagnosis, then recreate it so corruption cannot trap every
            // future launch in a failed-indexing loop.
            try archiveDatabaseAndReopen()
            try replaceAllOnce(with: entries, schemaVersion: schemaVersion)
        }
    }

    func apply(
        upserts: [IndexEntry],
        removing assetIDs: Set<String>,
        schemaVersion: Int
    ) throws {
        guard !upserts.isEmpty || !assetIDs.isEmpty else { return }
        try inTransaction {
            try delete(assetIDs)
            try upsert(upserts)
            try setMetadataValue(String(schemaVersion), forKey: "schema_version")
        }
    }

    /// Makes committed row-level changes durable and releases accumulated WAL
    /// pages without rewriting the photo table.
    func checkpoint() throws {
        try openIfNeeded()
        try execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil) == SQLITE_OK,
              let openedDatabase else {
            let message = openedDatabase.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let openedDatabase { sqlite3_close(openedDatabase) }
            throw StoreError.open(message)
        }
        database = openedDatabase

        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try execute("PRAGMA busy_timeout=3000;")
            try execute(
                "CREATE TABLE IF NOT EXISTS photo_entries ("
                    + "asset_id TEXT PRIMARY KEY NOT NULL, "
                    + "payload BLOB NOT NULL"
                    + ");"
            )
            try execute(
                "CREATE TABLE IF NOT EXISTS metadata ("
                    + "key TEXT PRIMARY KEY NOT NULL, "
                    + "value TEXT NOT NULL"
                    + ");"
            )
        } catch {
            sqlite3_close(openedDatabase)
            database = nil
            throw error
        }
    }

    private func replaceAllOnce(with entries: [String: IndexEntry], schemaVersion: Int) throws {
        try inTransaction {
            try execute("DELETE FROM photo_entries;")
            try upsert(Array(entries.values))
            try setMetadataValue(String(schemaVersion), forKey: "schema_version")
        }
    }

    private func archiveDatabaseAndReopen() throws {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }

        let fileManager = FileManager.default
        let suffix = ".invalid-\(Int(Date().timeIntervalSince1970))"
        for extensionSuffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + extensionSuffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: source.path + suffix)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }
        try openIfNeeded()
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try openIfNeeded()
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func upsert(_ entries: [IndexEntry]) throws {
        guard !entries.isEmpty else { return }
        let sql = "INSERT OR REPLACE INTO photo_entries (asset_id, payload) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for entry in entries {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            guard sqlite3_bind_text(statement, 1, entry.assetId, -1, sqliteTransient) == SQLITE_OK else {
                throw StoreError.bind(lastErrorMessage)
            }
            let data = try encoder.encode(entry)
            let bindResult = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(data.count), sqliteTransient)
            }
            guard bindResult == SQLITE_OK else {
                throw StoreError.bind(lastErrorMessage)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(lastErrorMessage)
            }
        }
    }

    private func delete(_ assetIDs: Set<String>) throws {
        guard !assetIDs.isEmpty else { return }
        let sql = "DELETE FROM photo_entries WHERE asset_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for assetID in assetIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            guard sqlite3_bind_text(statement, 1, assetID, -1, sqliteTransient) == SQLITE_OK else {
                throw StoreError.bind(lastErrorMessage)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(lastErrorMessage)
            }
        }
    }

    private func setMetadataValue(_ value: String, forKey key: String) throws {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, key, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, value, -1, sqliteTransient) == SQLITE_OK else {
            throw StoreError.bind(lastErrorMessage)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(lastErrorMessage)
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw StoreError.execute(message)
        }
    }

    private var lastErrorMessage: String {
        guard let database else { return "database unavailable" }
        return String(cString: sqlite3_errmsg(database))
    }

    private var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
