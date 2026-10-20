//
//  AppSignature.swift
//  KISSTranslator
//
//  Reads the running app's own code-signing team identifier.
//

import Foundation
import Security

/// Code-signing facts about the running app bundle.
///
/// Safari only lists a web extension whose *containing app* carries a real
/// Team Identifier. An ad-hoc signed or unsigned build (what CI and the
/// release workflow produce before a Developer ID pass) is silently omitted
/// from Safari → Settings → Extensions — the user clicks the onboarding
/// button, Safari opens, and the extension is nowhere to be found. Surfacing
/// the missing team in the UI turns that dead end into an explanation.
enum AppSignature {
    /// The Team Identifier recorded in this app's signature, or `nil` when the
    /// app is ad-hoc signed, unsigned, or its signature cannot be read.
    static var teamIdentifier: String? {
        var staticCode: SecStaticCode?
        let url = Bundle.main.bundleURL as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return nil }

        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// `true` when Safari will refuse to list this build's extension because
    /// the signature carries no real team (ad-hoc / unsigned).
    static var isAdHocOrUnsigned: Bool { teamIdentifier == nil }
}
