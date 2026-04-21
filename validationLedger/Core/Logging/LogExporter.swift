// validationLedger/Core/Logging/LogExporter.swift
// OSLogStore pull for DevMenu LogViewer (LOG-03). DEBUG-only concerns
// live in App/DevMenu/LogViewerViewController.swift; this file provides
// the API wrapper.

import OSLog
import Foundation

public struct LogExporter: Sendable {
    public init() {}

    /// Returns the last `interval` seconds of OSLog entries for the given subsystem.
    /// Entries are already scrubbed (PIIScrubber ran before they reached OSLog).
    public func fetch(since interval: TimeInterval, subsystem: String? = nil) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date(timeIntervalSinceNow: -interval))
        var predicate: NSPredicate?
        if let subsystem {
            predicate = NSPredicate(format: "subsystem == %@", subsystem)
        }
        let entries = try store.getEntries(at: since, matching: predicate)
        return entries.compactMap { ($0 as? OSLogEntryLog).flatMap { entry in
            "[\(entry.date)] \(entry.category): \(entry.composedMessage)"
        } }
    }
}
