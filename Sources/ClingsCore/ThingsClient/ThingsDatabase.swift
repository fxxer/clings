// ThingsDatabase.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GRDB

/// Direct SQLite access to the Things 3 database for fast reads.
/// Note: This is an undocumented API and may break with Things updates.
public final class ThingsDatabase: Sendable {
    private let dbPath: String

    /// Initialize with the Things 3 database path.
    public init() throws {
        // Find the Things database - it may be in a ThingsData-XXXX subdirectory
        let groupContainerBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac")

        // Try to find the database in any ThingsData-* subdirectory
        var dbPathFound: String?

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: groupContainerBase.path) {
            for item in contents where item.hasPrefix("ThingsData-") {
                let candidatePath = groupContainerBase
                    .appendingPathComponent(item)
                    .appendingPathComponent("Things Database.thingsdatabase/main.sqlite")
                if FileManager.default.fileExists(atPath: candidatePath.path) {
                    dbPathFound = candidatePath.path
                    break
                }
            }
        }

        // Fallback: try the old location (Things Database.thingsdatabase directly in container)
        if dbPathFound == nil {
            let fallbackPath = groupContainerBase
                .appendingPathComponent("Things Database.thingsdatabase/main.sqlite")
            if FileManager.default.fileExists(atPath: fallbackPath.path) {
                dbPathFound = fallbackPath.path
            }
        }

        guard let path = dbPathFound else {
            throw ThingsError.operationFailed("Things 3 database not found. Is Things 3 installed?")
        }

        self.dbPath = path
    }

    /// Open a read-only connection to the database.
    private func openDatabase() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: dbPath, configuration: config)
    }

    // MARK: - List Queries

    /// Fetch todos from a specific list view.
    public func fetchList(_ list: ListView) throws -> [Todo] {
        let db = try openDatabase()

        return try db.read { db in
            let sql: String
            let arguments: StatementArguments

            switch list {
            case .inbox:
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 0 AND trashed = 0 AND type = 0
                          AND start = 0 AND project IS NULL AND startDate IS NULL
                    ORDER BY "index"
                    """
                arguments = []

            case .today:
                let todayDays = daysSinceReferenceDate(Date())
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 0 AND trashed = 0 AND type = 0
                          AND (start = 1 OR startDate = ?)
                    ORDER BY todayIndex, "index"
                    """
                arguments = [todayDays]

            case .upcoming:
                let todayDays = daysSinceReferenceDate(Date())
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 0 AND trashed = 0 AND type = 0 AND startDate > ?
                    ORDER BY startDate, "index"
                    """
                arguments = [todayDays]

            case .anytime:
                let todayDays = daysSinceReferenceDate(Date())
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 0 AND trashed = 0 AND type = 0 AND start = 1
                          AND (startDate IS NULL OR startDate <= ?)
                    ORDER BY "index"
                    """
                arguments = [todayDays]

            case .someday:
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 0 AND trashed = 0 AND type = 0 AND start = 2
                    ORDER BY "index"
                    """
                arguments = []

            case .logbook:
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE status = 3 AND trashed = 0 AND type = 0
                    ORDER BY stopDate DESC
                    LIMIT 500
                    """
                arguments = []

            case .trash:
                sql = """
                    SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                           userModificationDate, project, area
                    FROM TMTask
                    WHERE trashed = 1 AND type = 0
                    ORDER BY "index"
                    """
                arguments = []
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return try self.hydrateTodos(rows, db: db)
        }
    }

    /// Fetch all projects.
    public func fetchProjects() throws -> [Project] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT uuid, title, notes, status, stopDate, deadline, creationDate, area
                FROM TMTask
                WHERE type = 1 AND trashed = 0 AND status = 0
                ORDER BY "index"
                """

            let rows = try Row.fetchAll(db, sql: sql)
            
            // Bulk fetch related data
            let projectIds = rows.map { $0["uuid"] as String }
            let areaIds = rows.compactMap { $0["area"] as String? }
            
            let tagsByTask = try self.bulkFetchTags(taskIds: projectIds, db: db)
            let areasById = try self.bulkFetchAreas(areaIds: areaIds, db: db)

            return try rows.map { row in
                let uuid: String = row["uuid"]
                let title: String = row["title"]
                let notes: String? = row["notes"]
                let statusInt: Int = row["status"]
                let areaUuid: String? = row["area"]

                let area = areaUuid.flatMap { areasById[$0] }
                let tags = tagsByTask[uuid] ?? []

                let deadline: Date? = (row["deadline"] as Int?).flatMap {
                    Date(timeIntervalSinceReferenceDate: TimeInterval($0))
                }
                let creationDate = Date(timeIntervalSinceReferenceDate: TimeInterval(row["creationDate"] as Int))

                return Project(
                    id: uuid,
                    name: title,
                    notes: notes,
                    status: statusFromInt(statusInt),
                    area: area,
                    tags: tags,
                    dueDate: deadline,
                    creationDate: creationDate
                )
            }
        }
    }

    /// Fetch all areas.
    public func fetchAreas() throws -> [Area] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = "SELECT uuid, title FROM TMArea ORDER BY \"index\""
            let rows = try Row.fetchAll(db, sql: sql)
            
            let areaIds = rows.map { $0["uuid"] as String }
            let tagsByArea = try self.bulkFetchTagsForAreas(areaIds: areaIds, db: db)

            return try rows.map { row in
                let uuid: String = row["uuid"]
                let title: String = row["title"]
                let tags = tagsByArea[uuid] ?? []

                return Area(id: uuid, name: title, tags: tags)
            }
        }
    }

    /// Fetch all tags.
    public func fetchTags() throws -> [Tag] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = "SELECT uuid, title FROM TMTag ORDER BY title"
            let rows = try Row.fetchAll(db, sql: sql)

            return rows.map { row in
                Tag(id: row["uuid"], name: row["title"])
            }
        }
    }

    /// Fetch all headings for a project (by UUID or name).
    public func fetchHeadings(projectId: String) throws -> [Heading] {
        let db = try openDatabase()

        return try db.read { db in
            // Resolve name → UUID if needed
            let resolvedId: String
            if projectId.contains(" ") || projectId.count < 20 {
                // Looks like a name — try to resolve to UUID
                let projectRow = try Row.fetchOne(db,
                    sql: "SELECT uuid FROM TMTask WHERE title = ? AND type = 1 AND trashed = 0 LIMIT 1",
                    arguments: [projectId])
                resolvedId = projectRow?["uuid"] ?? projectId
            } else {
                resolvedId = projectId
            }

            let rows = try Row.fetchAll(db,
                sql: """
                    SELECT uuid, title FROM TMTask
                    WHERE project = ? AND type = 2 AND trashed = 0
                    ORDER BY "index"
                    """,
                arguments: [resolvedId])

            return rows.map { row in
                Heading(id: row["uuid"], title: row["title"], projectId: resolvedId)
            }
        }
    }

    /// Fetch a single todo by ID.
    public func fetchTodo(id: String) throws -> Todo {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                       userModificationDate, project, area
                FROM TMTask
                WHERE uuid = ? AND type = 0
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else {
                throw ThingsError.notFound(id)
            }

            // Hydrate the single row
            let todos = try self.hydrateTodos([row], db: db)
            return todos[0]
        }
    }

    /// Search todos by text.
    public func search(query: String) throws -> [Todo] {
        let db = try openDatabase()

        return try db.read { db in
            let sql = """
                SELECT uuid, title, notes, status, stopDate, deadline, creationDate,
                       userModificationDate, project, area
                FROM TMTask
                WHERE type = 0 AND trashed = 0
                      AND (title LIKE ? OR notes LIKE ?)
                ORDER BY todayIndex, "index"
                LIMIT 100
                """

            let pattern = "%\\(query)%"
            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, pattern])
            return try self.hydrateTodos(rows, db: db)
        }
    }

    // MARK: - Bulk Fetching & Hydration

    private func hydrateTodos(_ rows: [Row], db: Database) throws -> [Todo] {
        if rows.isEmpty { return [] }

        // 1. Collect IDs
        let todoIds = rows.map { $0["uuid"] as String }
        let projectIds = rows.compactMap { $0["project"] as String? }
        let areaIds = rows.compactMap { $0["area"] as String? }

        // 2. Bulk fetch related data
        let tagsByTodo = try bulkFetchTags(taskIds: todoIds, db: db)
        let checklistByTodo = try bulkFetchChecklistItems(taskIds: todoIds, db: db)
        let projectsById = try bulkFetchProjectsBasic(projectIds: projectIds, db: db)
        let areasById = try bulkFetchAreas(areaIds: areaIds, db: db)

        // 3. Map rows to Todo objects
        return try rows.map { row in
            let uuid: String = row["uuid"]
            let title: String = row["title"]
            let notes: String? = row["notes"]
            let statusInt: Int = row["status"]
            let projectUuid: String? = row["project"]
            let areaUuid: String? = row["area"]

            let project = projectUuid.flatMap { projectsById[$0] }
            let area = areaUuid.flatMap { areasById[$0] }
            let tags = tagsByTodo[uuid] ?? []
            let checklistItems = checklistByTodo[uuid] ?? []

            let deadline: Date? = (row["deadline"] as Int?).flatMap {
                Date(timeIntervalSinceReferenceDate: TimeInterval($0))
            }
            let creationDate: Date = (row["creationDate"] as Double?).flatMap {
                Date(timeIntervalSinceReferenceDate: $0)
            } ?? Date()
            let modificationDate: Date = (row["userModificationDate"] as Double?).flatMap {
                Date(timeIntervalSinceReferenceDate: $0)
            } ?? creationDate

            return Todo(
                id: uuid,
                name: title,
                notes: notes,
                status: statusFromInt(statusInt),
                dueDate: deadline,
                tags: tags,
                project: project,
                area: area,
                checklistItems: checklistItems,
                creationDate: creationDate,
                modificationDate: modificationDate
            )
        }
    }

    private func bulkFetchTags(taskIds: [String], db: Database) throws -> [String: [Tag]] {
        if taskIds.isEmpty { return [:] }
        
        let sql = """
            SELECT tt.tasks, tag.uuid, tag.title
            FROM TMTaskTag AS tt
            JOIN TMTag AS tag ON tt.tags = tag.uuid
            WHERE tt.tasks IN (
        """
        
        // GRDB handles array arguments efficiently
        let placeholders = Array(repeating: "?", count: taskIds.count).joined(separator: ",")
        let fullSql = sql + placeholders + ")"
        
        let rows = try Row.fetchAll(db, sql: fullSql, arguments: StatementArguments(taskIds))
        
        var result: [String: [Tag]] = [:]
        for row in rows {
            let taskId: String = row["tasks"]
            let tag = Tag(id: row["uuid"], name: row["title"])
            result[taskId, default: []].append(tag)
        }
        return result
    }
    
    private func bulkFetchTagsForAreas(areaIds: [String], db: Database) throws -> [String: [Tag]] {
        if areaIds.isEmpty { return [:] }
        
        let sql = """
            SELECT at.areas, tag.uuid, tag.title
            FROM TMAreaTag AS at
            JOIN TMTag AS tag ON at.tags = tag.uuid
            WHERE at.areas IN (
        """
        
        let placeholders = Array(repeating: "?", count: areaIds.count).joined(separator: ",")
        let fullSql = sql + placeholders + ")"
        
        let rows = try Row.fetchAll(db, sql: fullSql, arguments: StatementArguments(areaIds))
        
        var result: [String: [Tag]] = [:]
        for row in rows {
            let areaId: String = row["areas"]
            let tag = Tag(id: row["uuid"], name: row["title"])
            result[areaId, default: []].append(tag)
        }
        return result
    }

    private func bulkFetchChecklistItems(taskIds: [String], db: Database) throws -> [String: [ChecklistItem]] {
        if taskIds.isEmpty { return [:] }
        
        let sql = "SELECT task, uuid, title, status FROM TMChecklistItem WHERE task IN ("
        let placeholders = Array(repeating: "?", count: taskIds.count).joined(separator: ",")
        let fullSql = sql + placeholders + ") ORDER BY \"index\""
        
        let rows = try Row.fetchAll(db, sql: fullSql, arguments: StatementArguments(taskIds))
        
        var result: [String: [ChecklistItem]] = [:]
        for row in rows {
            let taskId: String = row["task"]
            let item = ChecklistItem(
                id: row["uuid"],
                name: row["title"],
                completed: (row["status"] as Int) == 3
            )
            result[taskId, default: []].append(item)
        }
        return result
    }
    
    private func bulkFetchProjectsBasic(projectIds: [String], db: Database) throws -> [String: Project] {
        let uniqueIds = Array(Set(projectIds)) // Deduplicate
        if uniqueIds.isEmpty { return [:] }
        
        let sql = "SELECT uuid, title, status FROM TMTask WHERE type = 1 AND uuid IN ("
        let placeholders = Array(repeating: "?", count: uniqueIds.count).joined(separator: ",")
        let fullSql = sql + placeholders + ")"
        
        let rows = try Row.fetchAll(db, sql: fullSql, arguments: StatementArguments(uniqueIds))
        
        var result: [String: Project] = [:]
        for row in rows {
            let uuid: String = row["uuid"]
            let project = Project(
                id: uuid,
                name: row["title"],
                notes: nil,
                status: statusFromInt(row["status"]),
                area: nil,
                tags: [],
                dueDate: nil,
                creationDate: Date()
            )
            result[uuid] = project
        }
        return result
    }
    
    private func bulkFetchAreas(areaIds: [String], db: Database) throws -> [String: Area] {
        let uniqueIds = Array(Set(areaIds))
        if uniqueIds.isEmpty { return [:] }
        
        let sql = "SELECT uuid, title FROM TMArea WHERE uuid IN ("
        let placeholders = Array(repeating: "?", count: uniqueIds.count).joined(separator: ",")
        let fullSql = sql + placeholders + ")"
        
        let rows = try Row.fetchAll(db, sql: fullSql, arguments: StatementArguments(uniqueIds))
        
        var result: [String: Area] = [:]
        for row in rows {
            let uuid: String = row["uuid"]
            let area = Area(id: uuid, name: row["title"], tags: [])
            result[uuid] = area
        }
        return result
    }

    private func statusFromInt(_ value: Int) -> Status {
        switch value {
        case 0: return .open
        case 2: return .canceled
        case 3: return .completed
        default: return .open
        }
    }

    /// Calculate days since Cocoa reference date (January 1, 2001).
    /// Things 3 stores startDate as days, not seconds.
    private func daysSinceReferenceDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        // Reference date is Jan 1, 2001 00:00:00 UTC
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let components = calendar.dateComponents([.day], from: referenceDate, to: startOfDay)
        return components.day ?? 0
    }
}
