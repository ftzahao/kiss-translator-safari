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

    /// Refreshes `status` from Safari.
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
    func openSafariExtensionPreferences() async {
        guard !isOpeningPreferences else { return }
        isOpeningPreferences = true
        defer { isOpeningPreferences = false }

        if let failure = await SafariExtensionBridge.showPreferences(for: AppConfiguration.extensionBundleIdentifier) {
            errorMessage = failure
            // Refresh so the badge reflects reality (e.g. extension removed).
            await refreshStatus()
            return
        }
        errorMessage = nil
        NSApp.terminate(nil)
    }
}
