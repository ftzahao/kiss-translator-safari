//
//  AppConfiguration.swift
//  KISSTranslator Extension
//
//  Single source of truth for the native bundle metadata and links.
//
//  This file is compiled into BOTH targets: the app target adds it as a
//  source file (see `sources` for KISSTranslator in config/project.yml) and
//  the extension target picks it up from extension/Sources. Package-internal
//  types declared in extension/Sources are therefore apt to grow
//  extension-only APIs — put app-only code in app/Sources instead.
//
//  These values mirror `config/build.config.mjs`. If a bundle identifier
//  changes there, change it here as well.
//

import Foundation

enum AppConfiguration {
    /// Marketing name shown in the UI and in Safari's extension settings.
    static let displayName = "KISS Translator"

    /// The main app's bundle identifier.
    static let bundleIdentifier = "com.ftzahao.kisstranslator"

    /// The Safari web extension's bundle identifier.
    ///
    /// `SFSafariApplication.showPreferencesForExtension(withIdentifier:)` and
    /// `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)`
    /// must receive *this* identifier, not the containing app's.
    static let extensionBundleIdentifier = "com.ftzahao.kisstranslator.extension"

    /// Upstream open-source project.
    static let upstreamURL = URL(string: "https://github.com/fishjar/kiss-translator")!

    /// This wrapper project.
    static let projectURL = URL(string: "https://github.com/ftzahao/kiss-translator-safari")!

    /// Repository whose GitHub Releases are checked for updates, as
    /// `owner/name`. The update checker queries
    /// `https://api.github.com/repos/<this>/releases/latest`.
    static let updatesRepository = "ftzahao/kiss-translator-safari"

    /// All releases, for the "查看全部版本" link.
    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(updatesRepository)/releases")!
    }

    /// Upstream license (GPL-3.0).
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// `CFBundleShortVersionString` of the running app, e.g. "2.1.1".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// `CFBundleVersion` of the running app, e.g. "1".
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
