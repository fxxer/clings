// SchemaIntrospector.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GRDB

/// Errors from schema introspection.
public enum SchemaIntrospectorError: LocalizedError {
    case invalidTableName(String)
    case tableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTableName(let name):
            return "Table name '\(name)' is not in the allowed list"
        case .tableNotFound(let name):
            return "Table '\(name)' does not exist in the database"
        }
    }
}

/// Introspects SQLite table schemas using PRAGMA table_info.
///
/// Used by schema drift tests to compare the live Things 3 database
/// against a known baseline.
public enum SchemaIntrospector {

    /// Column metadata from PRAGMA table_info.
    public struct ColumnInfo: Codable, Equatable, Sendable {
        public let cid: Int
        public let name: String
        public let type: String
        public let notnull: Int
        public let pk: Int
    }

    /// Schema for a single table.
    public struct TableSchema: Codable, Equatable, Sendable {
        public let columns: [ColumnInfo]
        public let column_count: Int
    }

    /// Known Things 3 table names. Only these are allowed for introspection.
    private static let allowedTables: Set<String> = [
        "TMTask", "TMArea", "TMTag", "TMTaskTag", "TMAreaTag", "TMChecklistItem"
    ]

    /// Introspect the schema of specified tables from a SQLite database.
    ///
    /// - Parameters:
    ///   - databasePath: Path to the SQLite file.
    ///   - tables: Table names to introspect. Must be in the allowlist.
    /// - Returns: Dictionary mapping table name to its schema.
    /// - Throws: If a table name is not in the allowlist.
    public static func introspect(
        databasePath: String,
        tables: [String]
    ) throws -> [String: TableSchema] {
        for table in tables {
            guard allowedTables.contains(table) else {
                throw SchemaIntrospectorError.invalidTableName(table)
            }
        }

        var config = Configuration()
        config.readonly = true
        let dbQueue = try DatabaseQueue(path: databasePath, configuration: config)

        return try dbQueue.read { db in
            var schemas: [String: TableSchema] = [:]

            for table in tables {
                // PRAGMA does not support bound parameters for table names.
                // Safety is enforced by the allowlist check above; do not remove it.
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                guard !rows.isEmpty else {
                    throw SchemaIntrospectorError.tableNotFound(table)
                }
                let columns = rows.map { row in
                    ColumnInfo(
                        cid: row["cid"],
                        name: row["name"],
                        type: row["type"],
                        notnull: row["notnull"],
                        pk: row["pk"]
                    )
                }
                schemas[table] = TableSchema(
                    columns: columns,
                    column_count: columns.count
                )
            }

            return schemas
        }
    }
}
