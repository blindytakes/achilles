// HeroTransition.swift
//
// Environment keys that flow the matched-geometry namespace and carousel
// state from ThrowbaksApp down to YearCarouselCard and
// TutorialEnabledLoadedYearContentView without prop-drilling.

import SwiftUI

private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct HeroYearKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct ShowCarouselKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
    var heroYear: Int? {
        get { self[HeroYearKey.self] }
        set { self[HeroYearKey.self] = newValue }
    }
    var showCarousel: Bool {
        get { self[ShowCarouselKey.self] }
        set { self[ShowCarouselKey.self] = newValue }
    }
}
