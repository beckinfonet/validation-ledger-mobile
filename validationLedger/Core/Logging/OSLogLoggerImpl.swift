// validationLedger/Core/Logging/OSLogLoggerImpl.swift
import OSLog

final class OSLogLoggerImpl: Logger {
    private let osLog: os.Logger
    private let scrubber: PIIScrubber

    init(subsystem: String, category: String, scrubber: PIIScrubber = .default) {
        self.osLog = os.Logger(subsystem: subsystem, category: category)
        self.scrubber = scrubber
    }

    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {
        let scrubbed = scrubber.scrub(fields)
        let fieldsString = scrubbed.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        osLog.log(level: level.osLogType, "\(event.name, privacy: .public) \(fieldsString, privacy: .public)")
    }

    func log(_ level: LogLevel, _ message: String) {
        let scrubbed = scrubber.scrubString(message)
        osLog.log(level: level.osLogType, "\(scrubbed, privacy: .public)")
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        }
    }
}
