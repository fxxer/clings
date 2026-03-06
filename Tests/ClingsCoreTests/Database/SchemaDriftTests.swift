// SchemaDriftTests.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ClingsCore

/// Detects schema changes in the live Things 3 database.
///
/// These tests compare the installed Things 3 database schema against a
/// checked-in baseline. They skip automatically when Things 3 is not installed
/// (e.g., in CI environments).
final class SchemaDriftTests: XCTestCase {

    private static let trackedTables = [
        "TMTask", "TMArea", "TMTag", "TMTaskTag", "TMAreaTag", "TMChecklistItem"
    ]

    private static let expectedTMTaskColumnCount = 41

    /// Path to the live Things 3 database, or nil if not found.
    private static var liveDatabasePath: String? {
        // Try to find via ThingsDatabase's discovery logic
        if let db = try? ThingsDatabase() {
            return db.path
        }
        return nil
    }

    /// Path to the schema baseline JSON.
    private static var baselinePath: String {
        // Walk up from the test binary to find the repo root
        let sourceFile = #filePath
        let testsDir = URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent()  // Database/
            .deletingLastPathComponent()  // ClingsCoreTests/
            .deletingLastPathComponent()  // Tests/
        return testsDir
            .appendingPathComponent("SchemaBaseline")
            .appendingPathComponent("schema-baseline.json")
            .path
    }

    // MARK: - Tests

    func testSchemaMatchesBaseline() throws {
        guard let dbPath = Self.liveDatabasePath else {
            throw XCTSkip("Things 3 database not found (not installed or no access)")
        }

        let baselineData = try Data(contentsOf: URL(fileURLWithPath: Self.baselinePath))
        let baseline = try JSONDecoder().decode(
            [String: SchemaIntrospector.TableSchema].self,
            from: baselineData
        )

        let liveSchema = try SchemaIntrospector.introspect(
            databasePath: dbPath,
            tables: Self.trackedTables
        )

        for table in Self.trackedTables {
            guard let baselineTable = baseline[table] else {
                XCTFail("Missing baseline for table \(table)")
                continue
            }
            guard let liveTable = liveSchema[table] else {
                XCTFail("Table \(table) not found in live database")
                continue
            }

            // Compare column counts
            if baselineTable.column_count != liveTable.column_count {
                let baselineNames = Set(baselineTable.columns.map(\.name))
                let liveNames = Set(liveTable.columns.map(\.name))
                let added = liveNames.subtracting(baselineNames)
                let removed = baselineNames.subtracting(liveNames)
                XCTFail("""
                    Schema drift in \(table): \
                    baseline has \(baselineTable.column_count) columns, \
                    live has \(liveTable.column_count) columns. \
                    Added: \(added.sorted()). \
                    Removed: \(removed.sorted()). \
                    Run scripts/update-schema-baseline.sh to update.
                    """)
                continue
            }

            // Compare column details (use indices, not zip, to avoid silently dropping extras)
            let count = max(baselineTable.columns.count, liveTable.columns.count)
            for i in 0..<count {
                guard i < baselineTable.columns.count else {
                    XCTFail("Extra column in live \(table) at index \(i): \(liveTable.columns[i].name)")
                    continue
                }
                guard i < liveTable.columns.count else {
                    XCTFail("Missing column in live \(table) at index \(i): \(baselineTable.columns[i].name)")
                    continue
                }
                let baseCol = baselineTable.columns[i]
                let liveCol = liveTable.columns[i]
                if baseCol != liveCol {
                    XCTFail("""
                        Schema drift in \(table).\(baseCol.name): \
                        baseline=\(baseCol), live=\(liveCol). \
                        Run scripts/update-schema-baseline.sh to update.
                        """)
                }
            }
        }
    }

    func testTMTaskHasExpectedColumnCount() throws {
        guard let dbPath = Self.liveDatabasePath else {
            throw XCTSkip("Things 3 database not found (not installed or no access)")
        }

        let schema = try SchemaIntrospector.introspect(
            databasePath: dbPath,
            tables: ["TMTask"]
        )

        let columnCount = schema["TMTask"]?.column_count ?? 0
        XCTAssertEqual(
            columnCount,
            Self.expectedTMTaskColumnCount,
            "TMTask column count changed from \(Self.expectedTMTaskColumnCount) to \(columnCount). " +
            "This may indicate a Things 3 update changed the schema."
        )
    }

    func testBaselineFileIsValid() throws {
        let baselineData = try Data(contentsOf: URL(fileURLWithPath: Self.baselinePath))
        let baseline = try JSONDecoder().decode(
            [String: SchemaIntrospector.TableSchema].self,
            from: baselineData
        )

        // All tracked tables should be in baseline
        for table in Self.trackedTables {
            XCTAssertNotNil(baseline[table], "Missing baseline entry for \(table)")
        }

        // TMTask should have 41 columns in baseline
        XCTAssertEqual(baseline["TMTask"]?.column_count, Self.expectedTMTaskColumnCount)
    }

    func testIntrospectorRejectsDisallowedTableName() throws {
        let builder = try TestDatabaseBuilder()
        XCTAssertThrowsError(
            try SchemaIntrospector.introspect(
                databasePath: builder.path,
                tables: ["DropTable; --"]
            )
        ) { error in
            XCTAssertTrue(
                error is SchemaIntrospectorError,
                "Expected SchemaIntrospectorError, got \(type(of: error))"
            )
        }
    }
}
