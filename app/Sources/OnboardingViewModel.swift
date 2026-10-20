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

    // MARK: - Updates

    /// State of the update check, surfaced by the footer's update row.
    enum UpdateState: Equatable {
        /// Not checked yet (or the check is disabled).
        case idle
        /// A check is in flight.
        case checking
        /// Running version is current.
        case upToDate(latest: String)
        /// A newer release exists.
        case available(UpdateRelease)
        /// The check could not complete; shown subtly, never as a hard error.
        case failed(String)
    }

    private(set) var updateState: UpdateState = .idle

    /// True while a check runs, to disable the manual "检查更新" link.
    var isCheckingForUpdates: Bool { updateState == .checking }

    /// The newer release, when one is available.
    var availableUpdate: UpdateRelease? {
        if case .available(let release) = updateState { return release }
        return nil
    }

    /// Injected for tests; defaults to the real GitHub endpoint.
    private let updateChecker: UpdateChecker
    /// Suppresses the automatic check in previews/tests.
    private let checksAutomatically: Bool

    init(
        updateChecker: UpdateChecker = UpdateChecker(),
        checksAutomatically: Bool = true
    ) {
        self.updateChecker = updateChecker
        self.checksAutomatically = checksAutomatically
    }

    /// Checks GitHub Releases for a newer build.
    ///
    /// Runs automatically once per launch and on demand from the footer link.
    /// Failures stay quiet: an offline user should not get an error banner for
    /// a background convenience check.
    func checkForUpdates() async {
        guard updateState != .checking else { return }
        updateState = .checking

        switch await updateChecker.check() {
        case .upToDate(let latest):
            updateState = .upToDate(latest: latest)
        case .updateAvailable(let release):
            updateState = .available(release)
        case .failed(let error):
            updateState = .failed(error.localizedDescription)
        }
    }

    /// Performs the startup check at most once per app launch.
    func checkForUpdatesIfNeeded() async {
        guard checksAutomatically, updateState == .idle else { return }
        await checkForUpdates()
    }

    /// Opens the release page, or the direct DMG when the release has one.
    func openUpdateDownload(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }

    /// Opens the releases list, for picking a different version.
    func openAllReleases() {
        NSWorkspace.shared.open(AppConfiguration.releasesPageURL)
    }

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
