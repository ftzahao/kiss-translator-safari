//
//  Design.swift
//  KISSTranslator
//
//  Onboarding window layout constants, and the macOS 26 "Liquid Glass"
//  opt-in.
//
//  ── Liquid Glass ──────────────────────────────────────────────────────────
//  Starting with the macOS 26 SDK, building against that SDK opts the app into
//  the Liquid Glass design -- unless the app opts back out with
//  `UIDesignRequiresCompatibility = YES` in its Info.plist. A binary built with
//  an older SDK (the earlier release was built with the macOS 15.5 SDK) keeps
//  the pre-26 appearance: opaque window chrome, old-style controls, no glass.
//  That is why the build "isn't Liquid Glass" even on macOS 26/27.
//
//  The SDK version is baked in at compile time, so the UI is tuned per SDK
//  here instead of relying on runtime checks that cannot see it. Do NOT add
//  `UIDesignRequiresCompatibility` to app/Info.plist: that would opt the app
//  back out of Liquid Glass.
//

import SwiftUI

enum Design {
    /// `true` when the app opts into the Liquid Glass appearance.
    ///
    /// - macOS 26 SDK (Xcode 26+) and later: the app is built against the
    ///   Liquid Glass design, hence glass objects are used.
    /// - Older SDKs (Xcode 16, macOS 14/15 targets): legacy appearance.
    static let usesLiquidGlass: Bool = {
        #if compiler(>=6.2)
        return true
        #else
        return false
        #endif
    }()
}

/// The single window's dimensions.
///
/// `OnboardingView` pins its content to exactly this size and the window is
/// content-sized (`.windowResizability(.contentSize)`), so anything that makes
/// the content taller than `height` clips — never let a row grow unbounded.
enum OnboardingLayout {
    static let width: CGFloat = 520
    static let height: CGFloat = 640
}
