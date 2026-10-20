//
//  SafariExtensionBridge.swift
//  KISSTranslator
//
//  Thin, Swift-6-friendly wrapper around the two SafariServices entry points
//  the onboarding window needs:
//
//    * `SFSafariApplication.showPreferencesForExtension(withIdentifier:)`
//    * `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)`
//
//  ── Concurrency design (do not "simplify" this) ────────────────────────────
//  SafariServices delivers both completion handlers on its own XPC reply
//  queue, **not** on the main thread, and gives them `@MainActor` isolation:
//  the header marks `getStateOfSafariExtension`'s handler `NS_SWIFT_UI_ACTOR`
//  (the Swift 6 import carries `@MainActor`), and `showPreferences…`'s handler
//  is inferred `@MainActor` from context.
//
//  The compiler therefore emits an executor check inside the ObjC→Swift thunk
//  that aborts the process (`dispatch_assert_queue_fail`) when Safari calls it
//  from the XPC thread. Two rules follow:
//
//    1. Handlers must be NON-isolated. They are created by plain top-level
//       `func`s (not `@MainActor` ones) — a closure literal written inside an
//       actor-isolated function inherits that isolation and will trap.
//    2. The handler must not touch UI state. It captures a `Sendable` box and
//       resumes the continuation on the main *thread* via `runOnMainThread`,
//       which enters no Task and so has no isolation to violate.
//
//  The C `NSError **` out-parameter is imported as `Error`, so handlers take
//  `(any Error)?`.
//

import Foundation
import SafariServices

@MainActor
enum SafariExtensionBridge {
    /// Whether Safari currently has *our* extension enabled.
    enum Status: Equatable {
        /// The state has not been queried yet (or is being re-queried).
        case unknown
        /// Safari reports the extension as enabled.
        case enabled
        /// Safari reports the extension as present but disabled (or not yet
        /// granted page access).
        case disabled
        /// The query itself failed (extension not installed for this Safari,
        /// Safari not running, sandbox denial, …).
        case failed(String)

        var isEnabled: Bool { self == .enabled }
    }

    /// Asks Safari for the current enabled state of the web extension.
    ///
    /// - Parameter identifier: The extension bundle identifier.
    /// - Returns: The bridged `Status`. Never throws: failures are surfaced as
    ///   `.failed(message)` so callers can render them inline.
    static func state(of identifier: String = AppConfiguration.extensionBundleIdentifier) async -> Status {
        await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)
            SFSafariExtensionManager.getStateOfSafariExtension(
                withIdentifier: identifier,
                completionHandler: makeStateHandler(box)
            )
        }
    }

    /// Opens Safari → Settings → Extensions with our extension selected.
    ///
    /// - Parameter identifier: The extension bundle identifier.
    /// - Returns: `nil` on success, or a human-readable error message.
    static func showPreferences(for identifier: String = AppConfiguration.extensionBundleIdentifier) async -> String? {
        await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)
            SFSafariApplication.showPreferencesForExtension(
                withIdentifier: identifier,
                completionHandler: makeShowPreferencesHandler(box)
            )
        }
    }
}

// MARK: - Non-isolated handler factories

/// Builds the non-isolated handler for the state query.
///
/// Deliberately a free function with no actor isolation so the returned
/// closure is non-isolated; see the note at the top of this file.
private func makeStateHandler(
    _ box: ContinuationBox<SafariExtensionBridge.Status>
) -> @Sendable (SFSafariExtensionState?, (any Error)?) -> Void {
    { state, error in
        // Both reads happen here, on Safari's XPC thread, so only Sendable
        // scalars reach the main thread below.
        let isEnabled = state?.isEnabled
        let message = error?.localizedDescription
        runOnMainThread {
            if let message {
                box.finish(with: .failed(message))
            } else if let isEnabled {
                box.finish(with: isEnabled ? .enabled : .disabled)
            } else {
                box.finish(with: .failed(String(
                    localized: "Safari 未返回扩展状态。",
                    comment: "Status error when Safari returns no extension state"
                )))
            }
        }
    }
}

/// Builds the non-isolated handler for `showPreferences…`.
private func makeShowPreferencesHandler(
    _ box: ContinuationBox<String?>
) -> @Sendable ((any Error)?) -> Void {
    { error in
        let message = error?.localizedDescription
        runOnMainThread {
            box.finish(with: message)
        }
    }
}

// MARK: - Helpers

/// Runs `body` on the main thread and **does not return until it has run**.
///
/// `DispatchQueue.main.async` (or `Task { @MainActor in … }`) can be deferred
/// indefinitely when the main queue happens to be blocked at dispatch time,
/// which silently strands the awaiter. The two branches below are the standard
/// workaround for that class of hang:
///
/// * already on the main thread → run inline (`MainActor.assumeIsolated`;
///   the main actor and the main thread share an executor);
/// * otherwise → block the calling thread until the main thread has run it.
///
/// The calling thread is Safari's XPC reply queue, which may block for the
/// microseconds `body` needs — it only resumes a continuation.
private func runOnMainThread(_ body: () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.sync(execute: body)
    }
}

/// Guards against a completion handler being invoked more than once (which
/// would trip a `CheckedContinuation` precondition failure), and lets the
/// continuation be resumed from any isolation domain.
private final class ContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(with value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
