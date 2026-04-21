// validationLedger/UI/DesignSystem/Typography.swift
// Phase-1 typography tokens. Uses UIFont.preferredFont(forTextStyle:) so
// Dynamic Type support is automatic (TechStack.md §6 Accessibility).

import UIKit

public extension DS {
    enum Typography {
        public static var largeTitle: UIFont { .preferredFont(forTextStyle: .largeTitle) }
        public static var title1:     UIFont { .preferredFont(forTextStyle: .title1) }
        public static var title2:     UIFont { .preferredFont(forTextStyle: .title2) }
        public static var headline:   UIFont { .preferredFont(forTextStyle: .headline) }
        public static var body:       UIFont { .preferredFont(forTextStyle: .body) }
        public static var callout:    UIFont { .preferredFont(forTextStyle: .callout) }
        public static var footnote:   UIFont { .preferredFont(forTextStyle: .footnote) }
        public static var caption:    UIFont { .preferredFont(forTextStyle: .caption1) }
    }
}
