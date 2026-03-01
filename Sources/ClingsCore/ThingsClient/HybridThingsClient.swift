// HybridThingsClient.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Hybrid Things client that uses SQLite for fast reads and JXA/AppleScript for writes.
public final class HybridThingsClient: ThingsClientProtocol, @unchecked Sendable {
    private let database: ThingsDatabase
    private let jxaBridge: JXABridge

    public init() throws {
        self.database = try ThingsDatabase()
        self.jxaBridge = JXABridge()
    }

    // MARK: - Reads (via SQLite - fast)

    public func fetchList(_ list: ListView) async throws -> [Todo] {
        try database.fetchList(list)
    }

    public func fetchProjects() async throws -> [Project] {
        try database.fetchProjects()
    }

    public func fetchAreas() async throws -> [Area] {
        try database.fetchAreas()
    }

    public func fetchTags() async throws -> [Tag] {
        try database.fetchTags()
    }

    public func fetchHeadings(projectId: String) async throws -> [Heading] {
        try database.fetchHeadings(projectId: projectId)
    }

    public func fetchTodo(id: String) async throws -> Todo {
        try database.fetchTodo(id: id)
    }

    public func search(query: String) async throws -> [Todo] {
        try database.search(query: query)
    }

    // MARK: - Writes (via URL Scheme - robust)

    public func createTodo(
        name: String,
        notes: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        project: String?,
        area: String?,
        heading: String?,
        checklistItems: [String]
    ) async throws -> String {
        var components = URLComponents(string: "things:///add")!
        var queryItems = [URLQueryItem(name: "title", value: name)]
        
        appendAuthToken(to: &queryItems)
        
        if let notes = notes {
            queryItems.append(URLQueryItem(name: "notes", value: notes))
        }
        
        if let when = when {
            queryItems.append(URLQueryItem(name: "when", value: formatDateForURL(when)))
        }
        
        if let deadline = deadline {
            queryItems.append(URLQueryItem(name: "deadline", value: formatDateForURL(deadline)))
        }
        
        if !tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        
        if let project = project {
            queryItems.append(URLQueryItem(name: "list", value: project))
        } else if let area = area {
            queryItems.append(URLQueryItem(name: "list", value: area))
        }
        
        if let heading = heading {
            queryItems.append(URLQueryItem(name: "heading", value: heading))
        }
        
        if !checklistItems.isEmpty {
            queryItems.append(URLQueryItem(name: "checklist-items", value: checklistItems.joined(separator: "\n")))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ThingsError.operationFailed("Could not construct Things URL")
        }
        
        let script = "open location \"\(url.absoluteString)\""
        _ = try await jxaBridge.executeAppleScript(script)
        
        return "sent-via-url-scheme"
    }

    public func createProject(
        name: String,
        notes: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        area: String?,
        headings: [String]
    ) async throws -> String {
        if !headings.isEmpty {
            return try await createProjectWithHeadingsJSON(
                name: name,
                notes: notes,
                when: when,
                deadline: deadline,
                tags: tags,
                area: area,
                headings: headings
            )
        }

        var components = URLComponents(string: "things:///add-project")!
        var queryItems = [URLQueryItem(name: "title", value: name)]
        
        appendAuthToken(to: &queryItems)
        
        if let notes = notes {
            queryItems.append(URLQueryItem(name: "notes", value: notes))
        }
        
        if let when = when {
            queryItems.append(URLQueryItem(name: "when", value: formatDateForURL(when)))
        }
        
        if let deadline = deadline {
            queryItems.append(URLQueryItem(name: "deadline", value: formatDateForURL(deadline)))
        }
        
        if !tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        
        if let area = area {
            queryItems.append(URLQueryItem(name: "area", value: area))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ThingsError.operationFailed("Could not construct Things URL")
        }
        
        let script = "open location \"\(url.absoluteString)\""
        _ = try await jxaBridge.executeAppleScript(script)
        
        return "sent-via-url-scheme"
    }

    public func updateProject(
        id: String,
        notes: String?,
        status: Status?
    ) async throws {
        var components = URLComponents(string: "things:///update-project")!
        var queryItems = [URLQueryItem(name: "id", value: id)]
        
        appendAuthToken(to: &queryItems)
        
        if let notes = notes {
            queryItems.append(URLQueryItem(name: "notes", value: notes))
        }
        
        if let status = status {
            switch status {
            case .completed: queryItems.append(URLQueryItem(name: "completed", value: "true"))
            case .canceled: queryItems.append(URLQueryItem(name: "canceled", value: "true"))
            default: break
            }
        }
        
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ThingsError.operationFailed("Could not construct update URL")
        }
        
        let script = "open location \"\(url.absoluteString)\""
        _ = try await jxaBridge.executeAppleScript(script)
    }

    private func createProjectWithHeadingsJSON(
        name: String,
        notes: String?,
        when: Date?,
        deadline: Date?,
        tags: [String],
        area: String?,
        headings: [String]
    ) async throws -> String {
        let headingItems = headings.map { [ "type": "heading", "attributes": ["title": $0] ] }
        
        var projectAttributes: [String: Any] = ["title": name]
        if let notes = notes { projectAttributes["notes"] = notes }
        if let when = when { projectAttributes["when"] = formatDateForURL(when) }
        if let deadline = deadline { projectAttributes["deadline"] = formatDateForURL(deadline) }
        if !tags.isEmpty { projectAttributes["tags"] = tags }
        if let area = area { projectAttributes["area"] = area }
        
        projectAttributes["items"] = headingItems
        
        let projectJson: [String: Any] = [
            "type": "project",
            "attributes": projectAttributes
        ]
        
        let data = try JSONSerialization.data(withJSONObject: [projectJson], options: [])
        let jsonString = String(data: data, encoding: .utf8)!
        
        var components = URLComponents(string: "things:///json")!
        var queryItems = [URLQueryItem(name: "data", value: jsonString)]
        
        appendAuthToken(to: &queryItems)
        components.queryItems = queryItems
        
        let script = "open location \"\(components.url!.absoluteString)\""
        _ = try await jxaBridge.executeAppleScript(script)
        
        return "sent-via-json-url"
    }

    // MARK: - Non-URL operations (JXA/AppleScript)

    public func completeTodo(id: String) async throws {
        let script = JXAScripts.completeTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func cancelTodo(id: String) async throws {
        let script = JXAScripts.cancelTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func deleteTodo(id: String) async throws {
        let script = JXAScripts.deleteTodo(id: id)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func moveTodo(id: String, toProject projectName: String) async throws {
        let script = JXAScripts.moveTodo(id: id, toProject: projectName)
        let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
        if !result.success {
            throw ThingsError.operationFailed(result.error ?? "Unknown error")
        }
    }

    public func updateTodo(id: String, name: String?, notes: String?, dueDate: Date?, tags: [String]?) async throws {
        if name != nil || notes != nil || dueDate != nil {
            let script = JXAScripts.updateTodo(id: id, name: name, notes: notes, dueDate: dueDate, tags: nil)
            let result = try await jxaBridge.executeJSON(script, as: MutationResult.self)
            if !result.success {
                throw ThingsError.operationFailed(result.error ?? "Unknown error")
            }
        }

        if let tags = tags {
            let tagScript = JXAScripts.setTodoTagsAppleScript(id: id, tags: tags)
            do {
                _ = try await jxaBridge.executeAppleScript(tagScript)
            } catch let error as JXAError {
                throw ThingsError.jxaError(error)
            }
        }
    }

    // MARK: - Tag Management

    public func createTag(name: String) async throws -> Tag {
        let script = JXAScripts.createTagAppleScript(name: name)
        do {
            let tagId = try await jxaBridge.executeAppleScript(script)
            return Tag(id: tagId, name: name)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    public func deleteTag(name: String) async throws {
        let script = JXAScripts.deleteTagAppleScript(name: name)
        do {
            _ = try await jxaBridge.executeAppleScript(script)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    public func renameTag(oldName: String, newName: String) async throws {
        let script = JXAScripts.renameTagAppleScript(oldName: oldName, newName: newName)
        do {
            _ = try await jxaBridge.executeAppleScript(script)
        } catch let error as JXAError {
            throw ThingsError.jxaError(error)
        }
    }

    // MARK: - Helpers

    private func formatDateForURL(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func appendAuthToken(to queryItems: inout [URLQueryItem]) {
        if let token = try? AuthTokenStore.loadToken() {
            queryItems.append(URLQueryItem(name: "auth-token", value: token))
        }
    }

    // MARK: - Open (disabled)

    public nonisolated func openInThings(id: String) throws {
        throw ThingsError.invalidState("Open command is disabled: URL schemes are not allowed.")
    }

    public nonisolated func openInThings(list: ListView) throws {
        throw ThingsError.invalidState("Open command is disabled: URL schemes are not allowed.")
    }
}

/// Factory to create the appropriate Things client.
public enum ThingsClientFactory {
    /// Create a Things client - tries hybrid first, falls back to JXA-only.
    public static func create() -> any ThingsClientProtocol {
        do {
            return try HybridThingsClient()
        } catch {
            return ThingsClient()
        }
    }
}
