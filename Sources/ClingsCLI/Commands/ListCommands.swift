// ListCommands.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import ArgumentParser
import ClingsCore

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "Suppress color output")
    var noColor = false
}

// MARK: - Base List Command

protocol ListCommand: AsyncParsableCommand {
    var output: OutputOptions { get }
    var listView: ListView { get }
}

extension ListCommand {
    func run() async throws {
        let client = try ThingsClientFactory.create()
        let todos = try await client.fetchList(listView)

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        // Include list name in JSON for API compatibility
        if output.json {
            print(formatter.format(todos: todos, list: listView.displayName))
        } else {
            print(formatter.format(todos: todos))
        }
    }
}

// MARK: - Today Command

struct TodayCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Show today's todos",
        discussion: """
        Displays all todos scheduled for today, including those with today's
        deadline or "when" date set to today.

        EXAMPLES:
          clings today                  Show today's todos
          clings t                      Alias for 'today'
          clings today --json           Output as JSON
          clings today --no-color       Disable colored output

        SEE ALSO:
          inbox, upcoming, anytime, someday
        """,
        aliases: ["t"]
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .today }
}

// MARK: - Inbox Command

struct InboxCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Show inbox todos",
        discussion: """
        Displays todos in the Inbox - items not yet organized into
        projects or scheduled for a specific date.

        The Inbox is the default capture location in Things. During
        weekly reviews, process these items by scheduling them or
        moving them to projects.

        EXAMPLES:
          clings inbox                  Show inbox items
          clings i                      Alias for 'inbox'
          clings inbox --json           Output as JSON

        SEE ALSO:
          today, review
        """,
        aliases: ["i"]
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .inbox }
}

// MARK: - Upcoming Command

struct UpcomingCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "upcoming",
        abstract: "Show upcoming todos",
        discussion: """
        Displays todos scheduled for future dates. These are items with
        a "when" date set to tomorrow or later.

        EXAMPLES:
          clings upcoming               Show upcoming todos
          clings u                      Alias for 'upcoming'
          clings upcoming --json        Output as JSON

        SEE ALSO:
          today, anytime, someday
        """,
        aliases: ["u"]
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .upcoming }
}

// MARK: - Anytime Command

struct AnytimeCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "anytime",
        abstract: "Show anytime todos",
        discussion: """
        Displays todos with no scheduled date - tasks you can do whenever
        you have time. These appear in the "Anytime" list in Things.

        EXAMPLES:
          clings anytime                Show anytime todos
          clings anytime --json         Output as JSON

        SEE ALSO:
          today, upcoming, someday
        """
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .anytime }
}

// MARK: - Someday Command

struct SomedayCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "someday",
        abstract: "Show someday todos",
        discussion: """
        Displays todos in the "Someday" list - ideas and tasks you might
        want to do eventually but aren't committed to yet.

        Review these periodically during your weekly review to decide
        if any should be moved to active lists.

        EXAMPLES:
          clings someday                Show someday items
          clings s                      Alias for 'someday'
          clings someday --json         Output as JSON

        SEE ALSO:
          anytime, review
        """,
        aliases: ["s"]
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .someday }
}

// MARK: - Logbook Command

struct LogbookCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logbook",
        abstract: "Show completed todos",
        discussion: """
        Displays recently completed todos from the Logbook.

        The Logbook contains your completed tasks, providing a
        record of accomplishments. Useful for:
        - Weekly reviews
        - Time tracking
        - Generating reports

        EXAMPLES:
          clings logbook                Show completed todos (last 500)
          clings l                      Alias for 'logbook'
          clings logbook --limit 1000   Show more results
          clings logbook --json         Output as JSON

        SEE ALSO:
          complete, stats
        """,
        aliases: ["l"]
    )

    @Option(name: .long, help: "Maximum number of results (default: 500)")
    var limit: Int = 500

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let todos = try await client.fetchList(.logbook, limit: limit)

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        if output.json {
            print(formatter.format(todos: todos, list: "Logbook"))
        } else {
            print(formatter.format(todos: todos))
        }
    }
}

// MARK: - Projects Command

struct ProjectsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List all projects",
        discussion: """
        Displays all projects from Things 3.

        Projects contain related todos working toward a specific goal.
        Use this to get an overview of all your active projects.

        EXAMPLES:
          clings projects               List all projects
          clings projects --json        Output as JSON

        SEE ALSO:
          areas, add --project
        """
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let projects = try await client.fetchProjects()

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(projects: projects))
    }
}

// MARK: - Areas Command

struct AreasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "areas",
        abstract: "List all areas",
        discussion: """
        Displays all areas from Things 3.

        Areas represent different spheres of responsibility in your life
        (e.g., "Work", "Personal", "Health"). Projects and todos can be
        assigned to areas for organization.

        EXAMPLES:
          clings areas                  List all areas
          clings areas --json           Output as JSON

        SEE ALSO:
          projects, add --area
        """
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let client = try ThingsClientFactory.create()
        let areas = try await client.fetchAreas()

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        print(formatter.format(areas: areas))
    }
}

// MARK: - Recent Command

struct RecentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recent",
        abstract: "Show recently created todos",
        discussion: """
        Displays todos created within the specified time period.
        Excludes completed and trashed todos.

        PERIOD FORMAT:
          3d   = last 3 days
          1w   = last week
          2m   = last 2 months

        EXAMPLES:
          clings recent           Show todos created in the last 7 days (default)
          clings recent 3d        Show todos created in the last 3 days
          clings recent 1w        Show todos created in the last week
          clings recent --json    Output as JSON

        SEE ALSO:
          today, logbook, filter
        """
    )

    @Argument(help: "Time period (e.g. 3d, 1w, 2m). Default: 7d")
    var period: String = "7d"

    @OptionGroup var output: OutputOptions

    func run() async throws {
        guard let since = parsePeriod(period) else {
            throw ThingsError.invalidState("Invalid period '\(period)'. Use format: 3d, 1w, 2m")
        }

        let client = try ThingsClientFactory.create()
        let todos = try await client.fetchRecent(since: since)

        let formatter: OutputFormatter = output.json
            ? JSONOutputFormatter()
            : TextOutputFormatter(useColors: !output.noColor)

        if output.json {
            print(formatter.format(todos: todos, list: "Recent"))
        } else {
            print(formatter.format(todos: todos))
        }
    }

    private func parsePeriod(_ str: String) -> Date? {
        let lower = str.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lower.hasSuffix("d"), let n = Int(lower.dropLast()) {
            return calendar.date(byAdding: .day, value: -n, to: now)
        }
        if lower.hasSuffix("w"), let n = Int(lower.dropLast()) {
            return calendar.date(byAdding: .weekOfYear, value: -n, to: now)
        }
        if lower.hasSuffix("m"), let n = Int(lower.dropLast()) {
            return calendar.date(byAdding: .month, value: -n, to: now)
        }
        return nil
    }
}

// MARK: - Trash Command

struct TrashCommand: ListCommand {
    static let configuration = CommandConfiguration(
        commandName: "trash",
        abstract: "Show trashed todos",
        discussion: """
        Displays todos that have been moved to the trash in Things 3.

        EXAMPLES:
          clings trash                  Show trashed todos
          clings trash --json           Output as JSON

        SEE ALSO:
          delete, logbook
        """
    )

    @OptionGroup var output: OutputOptions

    var listView: ListView { .trash }
}

// Note: TagsCommand moved to TagCommands.swift to support subcommands (add, delete, rename)
