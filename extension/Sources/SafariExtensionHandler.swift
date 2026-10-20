//
//  SafariExtensionHandler.swift
//  KISSTranslator Extension
//
//  `SFSafariExtensionHandler` subclass for the Safari *app extension* layer.
//
//  The web extension ships its own content scripts and a background service
//  worker, so no messages need to be relayed through native code today.
//  The class is still provided (and explicitly registered as the
//  `SFSafariExtensionHandling` entry point) because Safari expects the
//  handler to exist and because it is the natural place to add native
//  features — e.g. reading the page URL, storing credentials in the
//  Keychain — later on.
//

import Foundation
import os
import SafariServices

@objc(SafariExtensionHandler)
final class SafariExtensionHandler: SFSafariExtensionHandler {
    private let logger = Logger(subsystem: AppConfiguration.extensionBundleIdentifier, category: "ExtensionHandler")

    /// Called when one of the web extension's content scripts dispatches a
    /// message to the native layer.
    ///
    /// Intentionally a no-op: KISS Translator's content scripts talk to its
    /// own background service worker directly. If a native reply is ever
    /// required, use `page.dispatchMessageToScript(withName:userInfo:)` here.
    override func messageReceived(withName messageName: String,
                                  from page: SFSafariPage,
                                  userInfo: [String: Any]?)
    {
        logger.debug("messageReceived \(messageName, privacy: .public) (no native reply)")
    }

    /// Called when the containing app dispatches a message to the extension.
    override func messageReceivedFromContainingApp(withName messageName: String,
                                                   userInfo: [String: Any]?)
    {
        logger.debug("messageReceivedFromContainingApp \(messageName, privacy: .public) (no native reply)")
    }
}
