// validationLedger/UI/DesignSystem/Colors.swift
// Phase-1 design system color tokens. Skeleton only — expanded in Phase 3+.
// All colors default to iOS system semantic colors so dark-mode + Dynamic
// Type support is automatic.

import UIKit

public enum DS {
    public enum Colors {
        public static let primary:    UIColor = .systemBlue
        public static let background: UIColor = .systemBackground
        public static let surface:    UIColor = .secondarySystemBackground
        public static let label:      UIColor = .label
        public static let labelSecondary: UIColor = .secondaryLabel
        public static let separator:  UIColor = .separator
        // Phase 5 (05-UI-SPEC) — failed-upload status, rejection-reason text,
        // inline error labels, and destructive confirmation actions.
        public static let destructive: UIColor = .systemRed
        // Phase 9 (09-UI-SPEC § Banner lines 212-225, § Verdict block lines
        // 389-402) — caution-tier chain-integrity surfaces: yellow banner
        // background and 0.15-alpha verdict-block tint. The token consolidates
        // the "this needs attention" color hand across the chain-integrity
        // banner + verdict block + flagged-edge dash + caution halo so future
        // re-tinting touches one site. Uses `.systemYellow` so dark-mode and
        // dynamic-range adapt automatically (matches LimitedTrustBannerView
        // line 71 precedent of `UIColor.systemYellow`).
        public static let caution:     UIColor = .systemYellow
    }
}
