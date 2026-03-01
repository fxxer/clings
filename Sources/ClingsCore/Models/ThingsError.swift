// ThingsError.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Errors that can occur when interacting with Things 3.
public enum ThingsError: Error, LocalizedError {
    case operationFailed(String)
    case notFound(String)
    case invalidState(String)
    case jxaError(JXAError)

    public var errorDescription: String? {
        switch self {
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        case .notFound(let id):
            return "Item not found: \(id)"
        case .invalidState(let msg):
            return "Invalid state: \(msg)"
        case .jxaError(let error):
            return error.localizedDescription
        }
    }
}
