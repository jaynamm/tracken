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
