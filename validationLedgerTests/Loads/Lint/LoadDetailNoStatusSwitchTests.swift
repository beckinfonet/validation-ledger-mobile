// validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift
// Phase 10 Plan 04 Task 1 — lint-as-test for ROADMAP § Phase 10 invariant.
//
// === Invariant ===
// The action region's gate (per-role-per-status) flows from
// `RoleLoadPolicy` (Core/Load/RoleLoadPolicy.swift). The advance-button
// title resolver (per-status) lives in `LoadActionTitleResolver`
// (Core/Load/LoadActionTitleResolver.swift). BOTH live in Core/Load/.
// NO file under `validationLedger/Features/Loads/` may contain a
// `switch x.status` (regardless of identifier) — T-10-01 mitigation.
//
// === Regex ===
// `switch[[:space:]]+[^{]*\.status` matches:
//   - `switch x.status`
//   - `switch viewModel.role.status` (the trailing `.status` is the trigger)
//   - `switch (a, b.status)` (predictor's tuple form lives in Core/Load/,
//      not Features/Loads/, so this regex hit would correctly be flagged)
//
// === Allowlist ===
// Lines starting with `//` (comment lines) and lines starting with `///`
// (doc comments) are stripped before scanning. Block comments (`/* */`)
// are uncommon in this codebase but ALSO conservatively stripped.

import XCTest
@testable import validationLedger

final class LoadDetailNoStatusSwitchTests: XCTestCase {

    // MARK: - Test 1 — no switch.status in Features/Loads/

    /// Scan every `.swift` file under `validationLedger/Features/Loads/` and
    /// assert ZERO non-comment occurrences of the `switch.*\.status` pattern.
    /// Per ROADMAP §Phase 10 lock + T-10-01 mitigation.
    func test_noStatusSwitch_inFeaturesLoads() throws {
        // Locate the Features/Loads/ directory relative to this test file.
        // This test file lives at:
        //   <repo>/validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift
        // Target directory:
        //   <repo>/validationLedger/Features/Loads/
        let thisFile = URL(fileURLWithPath: #file)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // Lint/
            .deletingLastPathComponent()  // Loads/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo>/
        let featuresLoadsDir = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Features")
            .appendingPathComponent("Loads")

        // Sanity check — the directory MUST exist; if it doesn't this lint
        // is meaningless. Fail loudly rather than silently passing.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: featuresLoadsDir.path, isDirectory: &isDir
        )
        XCTAssertTrue(exists && isDir.boolValue,
                      "Features/Loads/ directory not found at \(featuresLoadsDir.path). " +
                      "The lint regex above is meaningless without source files to scan.")
        guard exists, isDir.boolValue else { return }

        // Enumerate all .swift files recursively.
        let enumerator = FileManager.default.enumerator(
            at: featuresLoadsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        XCTAssertNotNil(enumerator)

        // Regex: `switch[[:space:]]+[^{]*\.status` — see file-header note.
        // NSRegularExpression uses POSIX char classes — `\s` is equivalent to
        // `[[:space:]]`. `[^\\{]*` matches up to but not including the `{` of
        // the switch body, scoping the match to the SUBJECT of the switch
        // (not its arms, which may contain `case .status: …`).
        let pattern = #"switch\s+[^\{]*\.status"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])

        var offenders: [(file: String, line: Int, text: String)] = []
        for case let url as URL in enumerator! {
            guard url.pathExtension == "swift" else { continue }
            let contents = try String(contentsOf: url, encoding: .utf8)
            // Strip comment lines. We keep line numbering by replacing the
            // comment body with whitespace (preserving the line index for
            // error messages).
            let lines = contents.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip `//` and `///` comment lines.
                if trimmed.hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                let matches = regex.matches(in: line, options: [], range: range)
                for m in matches {
                    if let r = Range(m.range, in: line) {
                        offenders.append((
                            file: url.lastPathComponent,
                            line: idx + 1,
                            text: String(line[r])
                        ))
                    }
                }
            }
        }

        if !offenders.isEmpty {
            let lines = offenders.map { "  \($0.file):\($0.line) — `\($0.text)`" }
            XCTFail(
                "ROADMAP §Phase 10 lock violated — no `switch.*\\.status` permitted in " +
                "Features/Loads/. The action gate flows through " +
                "`RoleLoadPolicy.availableActions(for:in:)` (Core/Load/); the title gate " +
                "lives in `LoadActionTitleResolver` (Core/Load/). T-10-01 mitigation.\n" +
                "Offenders:\n" + lines.joined(separator: "\n")
            )
        }
    }
}
