//
//  trackenApp.swift
//  tracken
//
//  Created by jave on 9/4/26.
//

import SwiftUI
import AppKit

/// Keeps tracken out of the Dock and the regular app menu so its single
/// MenuBarExtra is the only persistent app entry shown by macOS.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct trackenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Single shared source of truth for usage + connection state.
    @State private var store = UsageStore()

    var body: some Scene {
        // The app launches as a normal window.
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
        }
        .windowResizability(.contentSize)

        // Dedicated Settings window (⌘,).
        Settings {
            SettingsView()
                .environment(store)
        }

        // The app has one persistent menu bar entry.
        MenuBarExtra(
            "tracken",
            systemImage: "gauge.with.dots.needle.67percent"
        ) {
            MenuBarView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
