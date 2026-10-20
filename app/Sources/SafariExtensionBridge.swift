//
//  SafariExtensionBridge.swift
//  KISSTranslator
//
//  Thin, Swift-6-friendly wrapper around the SafariServices entry points the
//  onboarding window needs:
//
//    * `SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:)`
//    * `SFSafariApplication.showPreferencesForExtension(withIdentifier:)`
//
//  ── Why this file is written the way it is (do not "simplify" it) ─────────
//
//  SafariServices delivers every completion handler on its own XPC reply queue
//  — `com.apple.NSXPCConnection.user.com.apple.SafariServices.ExtensionHelper`
//  — and *never* on the main thread. The Swift 6 importer nevertheless gives
//  the replies a MainActor-isolated signature (`getStateOfSafariExtension` is
//  marked `NS_SWIFT_UI_ACTOR` in the headers, and
//  `showPreferencesForExtension` is inferred `@MainActor` from context). The
//  compiler then emits an executor assertion inside the ObjC→Swift thunk that
//  calls `dispatch_assert_queue(main)`, which **traps the process** as soon as
//  Safari replies — on the very first launch, before the user can do anything.
//
//  Shipped 2.1.1 builds crashed exactly this way (`EXC_BREAKPOINT` /
//  `dispatch_assert_queue_fail` in
//  `closure #1 in static SafariExtensionBridge.state(of:)`). The crash report
//  is reproducible in one line:
//
//      SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:) { _, _ in
//          print(Thread.isMainThread)   // false
//      }
//
//  The fix is two rules, both load-bearing:
//
//    1. Never pass a closure literal written in MainActor context to
//       SafariServices. Safari calls the reply *block* from that plain queue,
//       so the block must be non-isolated: every call goes through the free
//       functions at the bottom of this file, which create the handler with
//       an explicit non-isolated closure type and pass it to the API.
//    2. Never await the reply from an actor-isolated closure: the
//       `CheckedContinuation` is set up inside non-isolated helpers
//       (`awaitStateReply` / `awaitPreferencesReply`), and the reply hops to
//       the main actor with `Task { @MainActor in … }` from inside the
//       non-isolated handler, where no isolation is assumed.
//
//  Calls that never get a reply (Safari quit, XPC wedged, extension unknown)
//  are bounded by `timeout` so the UI can never hang on a spinner.
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
        /// Safari not running, XPC denial, timeout, …).
        case failed(String)

        var isEnabled: Bool { self == .enabled }
    }

    /// How long a Safari round-trip may take before the UI gives up and shows
    /// a retry affordance instead of spinning forever.
    static let timeout: Duration = .seconds(5)

    /// Reply from a Safari round-trip: the answer, or a user-facing message.
    /// A small local type instead of `Result<_, String>` because `String` is
    /// not an `Error`.
    enum Reply<Value: Sendable>: Sendable {
        case value(Value)
        case failure(String)
    }

    // MARK: - State query

    /// Asks Safari for the current enabled state of the web extension.
    ///
    /// - Parameter identifier: The extension's bundle identifier.
    /// - Returns: The bridged `Status`. Never throws: failures are surfaced as
    ///   `.failed(message)` so callers can render them inline.
    static func state(of identifier: String = AppConfiguration.extensionBundleIdentifier) async -> Status {
        let outcome = await awaitStateReply(identifier, timeout: timeout)

        switch outcome {
        case .none:
            return .failed(String(
                localized: "Safari 未在限定时间内返回扩展状态。",
                comment: "Status error when Safari does not reply in time"
            ))
        case .some(.value(let isEnabled)):
            return isEnabled ? .enabled : .disabled
        case .some(.failure(let message)):
            return .failed(message)
        }
    }

    // MARK: - Opening Safari

    /// Result of asking Safari to open its extension settings.
    enum PreferencesResult: Equatable {
        /// Safari opened Settings → Extensions.
        case opened
        /// SafariServices accepted the call but no reply arrived; Safari has
        /// been launched/activated instead, which lands the user one step away.
        case fellBackToSafari
        /// Nothing could be opened; the message is fit for the UI.
        case failed(String)
    }

    /// Opens Safari → Settings → Extensions with our extension selected.
    ///
    /// Falls back to Safari's own Extensions pane (Apple Events) when Safari
    /// does not answer, because the extension-scoped call is unreliable while
    /// the extension is not yet approved (it reports `SFErrorDomain` error 1
    /// and does nothing visible).
    static func openPreferences(for identifier: String = AppConfiguration.extensionBundleIdentifier) async -> PreferencesResult {
        let outcome = await awaitPreferencesReply(identifier, timeout: timeout)

        switch outcome {
        case .some(.value):
            return .opened
        case .some(.failure(let message)):
            return .failed(message)
        case .none:
            // No reply: at least land the user in Safari's extension pane.
            // This is the common case for ad-hoc signed or not-yet-approved
            // extensions, where the scoped call silently returns error 1.
            openSafariExtensionSettings()
            return .fellBackToSafari
        }
    }

    /// Opens Safari → Settings → Extensions (no specific extension).
    ///
    /// SafariServices exposes no "open the pane generically" API on macOS, so
    /// this activates Safari and asks it, over Apple Events, to open its
    /// preferences. It needs the `com.apple.security.automation.apple-events`
    /// entitlement (declared in `KISSTranslator.entitlements`); if that is
    /// denied the user still ends up in Safari, one click from the pane.
    static func openSafariExtensionSettings() {
        activateSafari()

        // Activate Safari first so the Apple Event targets a running app.
        let script = """
        tell application "Safari"
            activate
            Open Preferences
        end tell
        """
        // Best effort: if Apple Events are denied the user is still in Safari.
        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    /// Brings Safari forward, launching it when it is not running.
    static func activateSafari() {
        let safari = URL(fileURLWithPath: "/System/Applications/Safari.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: safari, configuration: configuration) { _, _ in }
    }
}

// MARK: - Awaiting a reply (non-isolated on purpose)

/// Awaits the state reply, or `nil` after `timeout`.
///
/// Deliberately a free, non-isolated function. Inside a `@MainActor` context
/// Swift 6 treats the `CheckedContinuation` operation closure as isolated,
/// which re-introduces a MainActor hop into the reply path; here nothing is
/// isolated, so the reply arrives through `Task { @MainActor in … }` in
/// `queryState`.
private func awaitStateReply(
    _ identifier: String,
    timeout: Duration
) async -> SafariExtensionBridge.Reply<Bool>? {
    await withTimeout(timeout) {
        await withCheckedContinuation { (continuation: CheckedContinuation<SafariExtensionBridge.Reply<Bool>?, Never>) in
            let box = ContinuationBox(continuation)
            queryState(identifier) { reply in box.finish(with: reply) }
        }
    }
}

/// Awaits the `showPreferences` reply, or `nil` after `timeout`.
private func awaitPreferencesReply(
    _ identifier: String,
    timeout: Duration
) async -> SafariExtensionBridge.Reply<Void>? {
    await withTimeout(timeout) {
        await withCheckedContinuation { (continuation: CheckedContinuation<SafariExtensionBridge.Reply<Void>?, Never>) in
            let box = ContinuationBox(continuation)
            showPreferences(identifier) { reply in box.finish(with: reply) }
        }
    }
}

/// Runs `operation`, giving up after `timeout`.
///
/// Implemented as a task group race so it never leaks a blocked thread: a
/// reply that arrives after the timeout is dropped by `ContinuationBox`.
private func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - Non-isolated SafariServices bridges

/// Queries the extension state. Must stay a free, non-isolated function: the
/// closure it hands to SafariServices must not be MainActor-isolated.
///
/// The compiler can only know that the reply block is non-isolated if the
/// closure type is spelled out explicitly: when it is inferred from context,
/// Swift 6 applies the MainActor-typed imported signature and emits the very
/// executor assertion that crashed 2.1.1 (`dispatch_assert_queue_fail`). So the
/// completion type below is written in full on purpose.
private func queryState(
    _ identifier: String,
    completion: @escaping @Sendable (SafariExtensionBridge.Reply<Bool>) -> Void
) {
    let handler: @Sendable (SFSafariExtensionState?, (any Error)?) -> Void = { state, error in
        // Runs on SafariServices' XPC queue. Read only Sendable scalars here.
        let result: SafariExtensionBridge.Reply<Bool>
        if let error {
            result = .failure(failureMessage(error))
        } else if let state {
            result = .value(state.isEnabled)
        } else {
            result = .failure(String(
                localized: "Safari 未返回扩展状态。",
                comment: "Status error when Safari returns no extension state"
            ))
        }
        Task { @MainActor in completion(result) }
    }
    SFSafariExtensionManager.getStateOfSafariExtension(
        withIdentifier: identifier,
        completionHandler: handler
    )
}

/// Asks Safari to show our extension's settings page. Non-isolated for the
/// same reason as `queryState` (explicit closure type, same rationale).
private func showPreferences(
    _ identifier: String,
    completion: @escaping @Sendable (SafariExtensionBridge.Reply<Void>) -> Void
) {
    let handler: @Sendable ((any Error)?) -> Void = { error in
        let result: SafariExtensionBridge.Reply<Void> = error.map { .failure(failureMessage($0)) } ?? .value(())
        Task { @MainActor in completion(result) }
    }
    SFSafariApplication.showPreferencesForExtension(
        withIdentifier: identifier,
        completionHandler: handler
    )
}

/// Renders an `SFErrorDomain` error without leaking the bare domain into the
/// UI (users saw "未能完成操作。(SFErrorDomain错误1。)" and had no idea what to do).
private func failureMessage(_ error: any Error) -> String {
    let nsError = error as NSError
    if nsError.domain == "SFErrorDomain", nsError.code == 1 {
        return String(
            localized: "Safari 无法打开扩展设置。请确认已在「Safari 设置 › 扩展」中启用了 KISS Translator。",
            comment: "SFErrorDomain error 1 shown when Safari refuses the preferences request"
        )
    }
    return error.localizedDescription
}

/// Guards against a completion handler being invoked more than once (which
/// would trip a `CheckedContinuation` precondition failure) — e.g. a reply
/// that arrives after the timeout already fired.
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
