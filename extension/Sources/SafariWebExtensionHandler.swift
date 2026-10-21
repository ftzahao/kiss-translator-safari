//
//  SafariWebExtensionHandler.swift
//  KISSTranslator Extension
//
//  Native-side message handler for the Safari web extension.
//
//  KISS Translator funnels *all* of its work through `browser.runtime`
//  messaging and the WebExtension APIs implemented by WebKit itself
//  (`storage`, `scripting`, `declarativeNetRequest`, …). It never needs a
//  native round-trip, so this principal class only answers the generic
//  "ping" request that Apple's template emits plus a `capabilities` query,
//  and returns a structured error for anything else.
//
//  Keeping the handler in place matters regardless: Safari instantiates it
//  when the web extension is loaded, and the `SafariWebExtensionHandler`
//  principal class must exist for `NSExtension` to resolve.
//

import Foundation
import os
import SafariServices

/// `NSExtensionPrincipalClass` from `extension/Info.plist`.
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: AppConfiguration.extensionBundleIdentifier, category: "NativeBridge")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let userInfo = item?.userInfo

        // Safari wraps the `browser.runtime.sendNativeMessage` payload in
        // `SFExtensionMessageKey`.
        let message = userInfo?[SFExtensionMessageKey]

        guard let dictionary = message as? [String: Any],
              let request = dictionary["message"] as? String else {
            // Some callers (and Safari's own probe) send the payload without
            // the outer `message` envelope. Treat that as a ping.
            logger.debug("Native message without envelope; replying with heartbeat")
            respond(in: context, payload: heartbeat())
            return
        }

        logger.debug("Native message: \(request, privacy: .public)")

        let reply: [String: Any]
        switch request {
        case "ping", "heartbeat":
            reply = heartbeat()
        case "capabilities":
            reply = [
                "handled": true,
                "capabilities": ["nativeBridge": true, "version": AppConfiguration.version],
            ]
        default:
            // Unknown requests are answered explicitly rather than silently
            // dropped, so web-side callers can fall back deterministically.
            reply = [
                "handled": false,
                "error": "Unsupported native request: \(request)",
                "version": AppConfiguration.version,
            ]
        }

        respond(in: context, payload: reply)
    }

    private func heartbeat() -> [String: Any] {
        [
            "handled": true,
            "message": "简约翻译运行正常",
            "version": AppConfiguration.version,
        ]
    }

    private func respond(in context: NSExtensionContext, payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
