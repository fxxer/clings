// DateParser.swift
// clings - A powerful CLI for Things 3
// Copyright (C) 2024 Dan Hart
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A powerful date parser using NSDataDetector.
public struct DateParser: Sendable {
    public static let shared = DateParser()
    
    private init() {}
    
    /// Parse a date string into a Date.
    /// Supports:
    /// - Relative: "today", "tomorrow", "yesterday"
    /// - Natural: "next friday", "dec 15", "october 3rd"
    /// - Explicit: "2024-12-31"
    /// - Offsets: "in 3 days"
    public func parse(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Handle simple relative terms manually for speed/precision
        if lower == "today" {
            return calendar.startOfDay(for: now)
        }
        if lower == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        if lower == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        }
        
        // 2. Handle "in X days" regex
        // NSDataDetector is sometimes flaky with "in X days" without more context
        if lower.hasPrefix("in ") && lower.hasSuffix(" days") {
            let numberPart = lower.dropFirst(3).dropLast(5).trimmingCharacters(in: .whitespaces)
            if let days = Int(numberPart) {
                return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
            }
        }
        
        // 3. Use NSDataDetector for everything else
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        
        // We need to provide a range.
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: range)
        
        if let firstMatch = matches.first, let date = firstMatch.date {
            // NSDataDetector often returns times. If the user didn't specify a time,
            // we might want to default to start of day, but Things 3 handles times too.
            // For now, return the date as-is.
            return date
        }
        
        // 4. Fallback for ISO8601/Simple dates if NSDataDetector missed them (unlikely but safe)
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        
        let simpleFormatter = DateFormatter()
        simpleFormatter.dateFormat = "yyyy-MM-dd"
        if let date = simpleFormatter.date(from: trimmed) {
            return date
        }
        
        return nil
    }
}
