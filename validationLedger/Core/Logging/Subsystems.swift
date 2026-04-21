// validationLedger/Core/Logging/Subsystems.swift
// OSLog subsystem constants — one per top-level Core/ module per D-17.
// New Core modules add a static constant here, not in the module's source files.

public enum LoggingSubsystem {
    public static let app        = "com.maldin.validationLedger.app"
    public static let networking = "com.maldin.validationLedger.networking"
    public static let auth       = "com.maldin.validationLedger.auth"
    public static let keystore   = "com.maldin.validationLedger.keystore"
    public static let storage    = "com.maldin.validationLedger.storage"
    public static let identity   = "com.maldin.validationLedger.identity"
    public static let navigation = "com.maldin.validationLedger.navigation"
}
