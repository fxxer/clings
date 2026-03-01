// Heading.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A heading separator within a Things 3 project.
public struct Heading: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let projectId: String

    public init(id: String, title: String, projectId: String) {
        self.id = id
        self.title = title
        self.projectId = projectId
    }
}
