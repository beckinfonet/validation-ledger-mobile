// validationLedger/Core/Logging/Logger.swift
import OSLog

public enum LogLevel: Int, Sendable { case trace, debug, info, warn, error }

public enum LogField: Hashable, Sendable {
    case phone           // E.164 → masked
    case fullName        // "Jane Doe" → "J. D."
    case driversLicense  // → [REDACTED:DL]
    case mcNumber        // → [REDACTED:MC]
    case dotNumber       // → [REDACTED:DOT]
    case email           // local part masked
    case coordinates     // REMOVED entirely
    case count           // safe — integer
    case duration        // safe — TimeInterval
    case event           // safe — string event name
}

public struct LogEvent: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public static let keychainWiped = LogEvent("keychain_wiped")
    public static let firstLaunchDetected = LogEvent("first_launch_detected")
}

public protocol Logger: AnyObject, Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any])
    func log(_ level: LogLevel, _ message: String)
}

public extension Logger {
    func trace(event: LogEvent, fields: [LogField: Any] = [:]) { log(.trace, event: event, fields: fields) }
    func trace(_ message: String) { log(.trace, message) }
    func debug(event: LogEvent, fields: [LogField: Any] = [:]) { log(.debug, event: event, fields: fields) }
    func debug(_ message: String) { log(.debug, message) }
    func info(event: LogEvent, fields: [LogField: Any] = [:]) { log(.info, event: event, fields: fields) }
    func info(_ message: String) { log(.info, message) }
    func warn(event: LogEvent, fields: [LogField: Any] = [:]) { log(.warn, event: event, fields: fields) }
    func warn(_ message: String) { log(.warn, message) }
    func error(event: LogEvent, fields: [LogField: Any] = [:]) { log(.error, event: event, fields: fields) }
    func error(_ message: String) { log(.error, message) }
}
