// DatabaseTestFixtures.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import ClingsCore

/// Pre-built database scenarios for testing.
///
/// Each method populates a `TestDatabaseBuilder` with a specific set of data
/// covering edge cases that the codebase must handle correctly.
enum DatabaseTestFixtures {

    // MARK: - Well-known IDs (stable across tests)

    static let inboxTaskId       = "inbox-task-001"
    static let todayTaskId       = "today-task-001"
    static let todayStartDateId  = "today-startdate-001"
    static let upcomingTaskId    = "upcoming-task-001"
    static let anytimeTaskId     = "anytime-task-001"
    static let somedayTaskId     = "someday-task-001"
    static let completedTaskId   = "completed-001"
    static let canceledTaskId    = "canceled-001"
    static let trashedTaskId     = "trashed-001"
    static let projectId         = "project-001"
    static let projectTaskId     = "project-task-001"
    static let areaId            = "area-001"
    static let areaTaskId        = "area-task-001"
    static let tagId             = "tag-001"
    static let taggedTaskId      = "tagged-task-001"
    static let checklistTaskId   = "checklist-task-001"
    static let recurringTaskId   = "recurring-task-001"
    static let unicodeTaskId     = "unicode-task-001"
    static let overdueTaskId     = "overdue-task-001"
    static let futureDeadlineId  = "future-deadline-001"
    static let headingId         = "heading-001"
    static let emptyNotesTaskId  = "empty-notes-001"
    static let longNotesTaskId   = "long-notes-001"
    static let secondTagId       = "tag-002"

    /// Today's packed date for startDate comparisons.
    static var todayPacked: Int {
        ThingsDateConverter.encodeDate(Date())
    }

    /// A future date (30 days from now) as packed integer.
    static var futurePacked: Int {
        let future = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        return ThingsDateConverter.encodeDate(future)
    }

    /// A past date (30 days ago) as packed integer.
    static var pastPacked: Int {
        let past = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return ThingsDateConverter.encodeDate(past)
    }

    // MARK: - Comprehensive Fixture

    /// Populates a builder with a comprehensive set of edge cases.
    ///
    /// Covers: inbox, today, upcoming, anytime, someday, logbook, trash,
    /// projects, areas, tags, checklists, recurring, unicode, overdue, etc.
    static func populateComprehensive(_ builder: TestDatabaseBuilder) {
        let now = Date().timeIntervalSince1970

        // -- Areas --
        builder.addArea(uuid: areaId, title: "Work", index: 0)

        // -- Tags --
        builder.addTag(uuid: tagId, title: "urgent", index: 0)
        builder.addTag(uuid: secondTagId, title: "low-priority", index: 1)

        // -- Project (type=1) --
        builder.addTask(
            uuid: projectId, title: "Ship v1.0", type: 1,
            status: 0, start: 1, area: areaId, index: 0
        )

        // -- Heading (type=2) - must be excluded from todo queries --
        builder.addTask(
            uuid: headingId, title: "Planning Phase", type: 2,
            project: projectId, index: 0
        )

        // -- Inbox todo (start=0, no project, no startDate) --
        builder.addTask(
            uuid: inboxTaskId, title: "Review PR",
            notes: "Check the failing tests", start: 0, index: 0
        )

        // -- Today todo (start=1, startDate=today) --
        builder.addTask(
            uuid: todayTaskId, title: "Write tests",
            start: 1, startDate: todayPacked, index: 0, todayIndex: 0
        )

        // -- Today via startDate == today (also start=1) --
        builder.addTask(
            uuid: todayStartDateId, title: "Scheduled for today",
            start: 1, startDate: todayPacked, index: 1, todayIndex: 1
        )

        // -- Upcoming (startDate in future) --
        builder.addTask(
            uuid: upcomingTaskId, title: "Future planning",
            start: 1, startDate: futurePacked, index: 0
        )

        // -- Anytime (start=1, no startDate) --
        builder.addTask(
            uuid: anytimeTaskId, title: "Refactor module",
            start: 1, index: 1, todayIndex: 2
        )

        // -- Someday (start=2) --
        builder.addTask(
            uuid: somedayTaskId, title: "Learn Rust",
            start: 2, index: 0
        )

        // -- Completed (status=3) --
        builder.addTask(
            uuid: completedTaskId, title: "Fix login bug",
            status: 3, start: 1, index: 0, stopDate: now
        )

        // -- Canceled (status=2) --
        builder.addTask(
            uuid: canceledTaskId, title: "Deprecated feature",
            status: 2, start: 1, index: 0
        )

        // -- Trashed --
        builder.addTask(
            uuid: trashedTaskId, title: "Trashed item",
            trashed: 1, start: 1, index: 0
        )

        // -- Task in project --
        builder.addTask(
            uuid: projectTaskId, title: "Write README",
            start: 1, project: projectId, index: 0, todayIndex: 3
        )

        // -- Task in area --
        builder.addTask(
            uuid: areaTaskId, title: "Weekly report",
            start: 1, area: areaId, index: 2, todayIndex: 4
        )

        // -- Tagged task --
        builder.addTask(
            uuid: taggedTaskId, title: "Urgent fix",
            start: 1, index: 3, todayIndex: 5
        )
        builder.addTaskTag(taskUuid: taggedTaskId, tagUuid: tagId)
        builder.addTaskTag(taskUuid: taggedTaskId, tagUuid: secondTagId)

        // -- Task with checklist --
        builder.addTask(
            uuid: checklistTaskId, title: "Deploy checklist",
            start: 1, index: 4, todayIndex: 6
        )
        builder.addChecklistItem(title: "Run tests", status: 3, index: 0, task: checklistTaskId)
        builder.addChecklistItem(title: "Update docs", status: 0, index: 1, task: checklistTaskId)
        builder.addChecklistItem(title: "Tag release", status: 0, index: 2, task: checklistTaskId)

        // -- Recurring task --
        builder.addTask(
            uuid: recurringTaskId, title: "Daily standup",
            start: 1, index: 5, todayIndex: 7,
            repeatingTemplate: "template-001"
        )

        // -- Unicode title --
        builder.addTask(
            uuid: unicodeTaskId, title: "Fix bug in \u{1F41B} tracker",
            notes: "Emoji and CJK: \u{4F60}\u{597D}\u{4E16}\u{754C}",
            start: 1, index: 6, todayIndex: 8
        )

        // -- Overdue deadline (past date, still open) --
        builder.addTask(
            uuid: overdueTaskId, title: "Overdue report",
            start: 1, deadline: pastPacked, index: 7, todayIndex: 9
        )

        // -- Future deadline --
        builder.addTask(
            uuid: futureDeadlineId, title: "Quarterly review",
            start: 1, deadline: futurePacked, index: 8, todayIndex: 10
        )

        // -- Empty notes --
        builder.addTask(
            uuid: emptyNotesTaskId, title: "No notes here",
            notes: "", start: 1, index: 9, todayIndex: 11
        )

        // -- Long notes --
        builder.addTask(
            uuid: longNotesTaskId, title: "Long notes task",
            notes: String(repeating: "Lorem ipsum dolor sit amet. ", count: 100),
            start: 1, index: 10, todayIndex: 12
        )

        // -- Area tag --
        builder.addAreaTag(areaUuid: areaId, tagUuid: tagId)
    }
}
