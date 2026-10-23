//
//  OnboardingViewModel.swift
//  KISSTranslator
//
//  State for the onboarding window.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    /// Current Safari-reported enabled state of the web extension.
    private(set) var status: SafariExtensionBridge.Status = .unknown

    /// `true` while a "show Safari preferences" call is in flight.
    private(set) var isOpeningPreferences = false

    /// User-facing error from the most recent action, if any.
    private(set) var errorMessage: String?

    var version: String { AppConfiguration.version }
    var build: String { AppConfiguration.build }

    /// `true` when this build carries no real signing team (ad-hoc/unsigned).
    ///
    /// Safari silently omits such builds from Settings → Extensions, so the
    /// onboarding must say so instead of letting the user chase a missing
    /// extension. Computed from the bundle's signature, never cached across
    /// launches — a re-signed copy relaunches with a different answer.
    var isAdHocSigned: Bool { AppSignature.isAdHocOrUnsigned }


    /// Refreshes `status` from Safari.
    ///
    /// Safe to call from `.task` at launch: `SafariExtensionBridge` never traps
    /// when Safari replies from its XPC queue, and every call is bounded by a
    /// timeout, so the badge can only end up in a definite state.
    func refreshStatus() async {
        status = await SafariExtensionBridge.state()
        // The status is rarely a "hard" failure even when the extension is
        // disabled, so a successful state query also clears stale errors.
        if case .failed = status {} else {
            errorMessage = nil
        }
    }

    /// Opens Safari's extension preferences. On success the onboarding window
    /// terminates the app, matching Apple's template behaviour, so that the
    /// user lands directly in Safari.
    ///
    /// `Button` actions run inside a SwiftUI `Task`, and an uncaught error or a
    /// hang there is invisible to the user (the button simply looks "dead").
    /// Every outcome therefore maps to either a visible message or a
    /// navigation away from this window.
    func openSafariExtensionPreferences() async {
        guard !isOpeningPreferences else { return }
        isOpeningPreferences = true
        defer { isOpeningPreferences = false }
        errorMessage = nil

        let result = await SafariExtensionBridge.openPreferences(for: AppConfiguration.extensionBundleIdentifier)
        switch result {
        case .opened, .fellBackToSafari:
            NSApp.terminate(nil)
        case .failed(let message):
            errorMessage = message
            // Make sure *something* is on screen even if Safari never appeared.
            SafariExtensionBridge.activateSafari()
            await refreshStatus()
        }
    }

    /// Re-queries Safari and, when Safari cannot answer, clears the stale
    /// message so the "重新检查状态" link stays responsive.
    func recheck() async {
        if case .failed = status {
            status = .unknown
        }
        await refreshStatus()
    }
}
