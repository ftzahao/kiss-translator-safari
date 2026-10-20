//
//  App.swift
//  KISSTranslator
//
//  SwiftUI entry point for the containing macOS app.
//

import AppKit
import SwiftUI

@main
struct KISSTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link(
                    String(localized: "项目主页", comment: "Help menu item linking to the wrapper project"),
                    destination: AppConfiguration.projectURL
                )
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The onboarding window has no document semantics; quit with the window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring the window to the front when launched from Finder/`open`.
        NSApp.activate(ignoringOtherApps: true)
    }
}
