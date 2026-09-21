//
//  trackenApp.swift
//  tracken
//
//  Created by jave on 9/4/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()

    private let singleInstanceCoordinator = SingleInstanceCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) {
        singleInstanceCoordinator.terminatePreviousInstances()
        NSApp.setActivationPolicy(.regular)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the bundled mascot directly, even if Launch Services still has
        // a cached icon for a previous build with the same bundle identifier.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        store.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
    }
}

@main
struct trackenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var store: UsageStore { appDelegate.store }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra(
            "tracken",
            image: "MenuBarIcon"
        ) {
            MenuBarView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
