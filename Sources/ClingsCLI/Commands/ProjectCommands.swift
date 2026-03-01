// ProjectCommands.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore
import Foundation

// MARK: - Project Command (Parent)

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects",
        discussion: """
        List and create projects in Things 3.

        Projects are containers for related todos working toward a specific goal.

        EXAMPLES:
          clings project                    List all projects (same as 'clings projects')
          clings project list               Same as above
          clings project add "Q1 Planning"  Create a new project
          clings project add "Sprint" --area "Work" --deadline 2025-01-31

        SEE ALSO:
          projects, add --project, areas
        """,
        subcommands: [
            ProjectListCommand.self,
            ProjectAddCommand.self,
            ProjectUpdateCommand.self,
            ProjectAddHeadingCommand.self,
        ],
        defaultSubcommand: ProjectListCommand.self
    )
}

// MARK: - Project List Command

struct ProjectListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all projects",
        aliases: ["ls"]
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = ThingsClientFactory.create()
        let projects = try await client.fetchProjects()

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(projects: projects))
    }
}

// MARK: - Project Add Command

struct ProjectAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new project",
        discussion: """
        Creates a new project in Things 3.

        EXAMPLES:
          clings project add "Q1 Planning"
          clings project add "Feature X" --notes "Implementation of feature X"
          clings project add "Sprint 12" --area "Work" --when today
          clings project add "Vacation" --deadline 2025-06-01 --tags "personal,planning"
          clings project add "Week #9" --area "Priority" --heading "Personal" --heading "Career" --heading "Family"
        """
    )

    @Argument(help: "Title of the project")
    var title: String

    @Option(name: .long, help: "Project notes/description")
    var notes: String?

    @Option(name: .long, help: "Area to assign project to")
    var area: String?

    @Option(name: .long, help: "When to start (today, tomorrow, YYYY-MM-DD)")
    var when: String?

    @Option(name: .long, help: "Deadline date (YYYY-MM-DD)")
    var deadline: String?

    @Option(name: .long, help: "Tags (comma-separated)")
    var tags: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Headings to add to the project (repeatable)")
    var heading: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ThingsError.invalidState("Project title cannot be empty")
        }

        let tagList = tags?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
        let headings = heading.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        // If headings requested, use things:///json (create, no auth token needed)
        if !headings.isEmpty {
            try createProjectWithHeadings(
                title: trimmedTitle, notes: notes, area: area, tags: tagList, headings: headings
            )
        } else {
            let client = ThingsClientFactory.create()
            let parsedWhen = try when.map { try parseWhenDate($0) }
            let parsedDeadline = try deadline.map { try parseWhenDate($0) }
            _ = try await client.createProject(
                name: trimmedTitle,
                notes: notes,
                when: parsedWhen,
                deadline: parsedDeadline,
                tags: tagList,
                area: area
            )
        }

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Created project: \(trimmedTitle)"))
    }

    /// Create project with headings via things:///json (no auth token required for creates).
    private func createProjectWithHeadings(
        title: String, notes: String?, area: String?, tags: [String], headings: [String]
    ) throws {
        var attrs: [String: Any] = ["title": title]
        if let notes = notes, !notes.isEmpty { attrs["notes"] = notes }
        if let area = area, !area.isEmpty { attrs["area"] = area }
        if !tags.isEmpty { attrs["tags"] = tags }

        let items: [[String: Any]] = headings.map { h in
            ["type": "heading", "attributes": ["title": h]]
        }
        attrs["items"] = items

        let data: [[String: Any]] = [["type": "project", "attributes": attrs]]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8),
              var components = URLComponents(string: "things:///json") else {
            throw ThingsError.operationFailed("Failed to construct Things URL for project creation")
        }
        components.queryItems = [URLQueryItem(name: "data", value: jsonString)]
        guard let url = components.url?.absoluteString else {
            throw ThingsError.operationFailed("Failed to build Things URL")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ThingsError.operationFailed("Failed to create project via Things URL (exit \(process.terminationStatus))")
        }
    }

    private func parseWhenDate(_ str: String) throws -> Date {
        let lower = str.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lower == "today" {
            return calendar.startOfDay(for: now)
        }
        if lower == "tomorrow" {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                return tomorrow
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: str) {
            return date
        }
        throw ThingsError.invalidState("Invalid date format: \(str). Use YYYY-MM-DD, 'today', or 'tomorrow'.")
    }
}

// MARK: - Project Add Heading Command

struct ProjectAddHeadingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-heading",
        abstract: "Add a heading to a project",
        discussion: """
        Adds a heading separator to an existing project by its UUID.
        Headings are used to group todos within a project.

        EXAMPLES:
          clings project add-heading "Personal" --project <uuid>
          clings project add-heading "Career" --project <uuid>
          clings project add-heading "Work" --project <uuid>
        """
    )

    @Argument(help: "Heading title")
    var title: String

    @Option(name: .long, help: "Project UUID to add heading to")
    var project: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        // Things 3 URL scheme only supports headings within NEW project creation.
        // There is no API (URL scheme, JXA, or AppleScript) for adding a heading to an existing project.
        // Use: clings project add "Title" --heading "H1" --heading "H2"  to create a project with headings.
        throw ThingsError.invalidState(
            "Adding headings to existing projects is not supported by Things 3's API.\n" +
            "Create headings at project creation time: clings project add \"Title\" --heading \"Personal\" --heading \"Career\"\n" +
            "Or add headings manually in the Things 3 app."
        )
    }
}

// MARK: - Project Update Command

struct ProjectUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a project's properties",
        discussion: """
        Update properties of an existing project by its UUID.

        EXAMPLES:
          clings project update <uuid> --notes "# Week #9\\n\\n## TOP 3"
          clings project update <uuid> --name "📍 Week #10"
          clings project update <uuid> --complete
          clings project update <uuid> --cancel
        """
    )

    @Argument(help: "The UUID of the project to update")
    var id: String

    @Option(name: .long, help: "New project name")
    var name: String?

    @Option(name: .long, help: "New project notes")
    var notes: String?

    @Flag(name: .long, help: "Mark project as completed")
    var complete = false

    @Flag(name: .long, help: "Mark project as canceled")
    var cancel = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        guard name != nil || notes != nil || complete || cancel else {
            throw ThingsError.invalidState(
                "No update options provided. Use --name, --notes, --complete, or --cancel."
            )
        }

        let client = ThingsClientFactory.create()
        // Interpret literal \n as newline (shell double-quote strings don't expand \n)
        let processedNotes = notes?.replacingOccurrences(of: "\\n", with: "\n")
        try await client.updateProject(id: id, name: name, notes: processedNotes, complete: complete, cancel: cancel)

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(message: "Updated project: \(id)"))
    }
}
