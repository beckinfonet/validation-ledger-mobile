// validationLedgerTests/Logging/LoggerLevelsTests.swift
import Testing
@testable import validationLedger

@Suite("Logger — 5-level contract (LOG-02)")
struct LoggerLevelsTests {
    @Test("LogLevel enum has all 5 cases in order")
    func fiveLevels() {
        #expect(LogLevel.trace.rawValue == 0)
        #expect(LogLevel.debug.rawValue == 1)
        #expect(LogLevel.info.rawValue == 2)
        #expect(LogLevel.warn.rawValue == 3)
        #expect(LogLevel.error.rawValue == 4)
    }

    @Test("Logger protocol extension methods compile and route to log(_:event:fields:) / log(_:_:)")
    func extensionMethodsRoute() {
        final class SpyLogger: Logger, @unchecked Sendable {
            var lastLevel: LogLevel?
            var lastEventName: String?
            var lastMessage: String?
            func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {
                lastLevel = level; lastEventName = event.name
            }
            func log(_ level: LogLevel, _ message: String) {
                lastLevel = level; lastMessage = message
            }
        }
        let spy = SpyLogger()
        spy.info(event: .firstLaunchDetected, fields: [.count: 0])
        #expect(spy.lastLevel == .info)
        #expect(spy.lastEventName == "first_launch_detected")

        spy.error(event: .keychainWiped)
        #expect(spy.lastLevel == .error)

        spy.info("hello world")
        #expect(spy.lastMessage == "hello world")
    }
}
