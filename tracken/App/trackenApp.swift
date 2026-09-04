//
//  trackenApp.swift
//  tracken
//
//  Created by jave on 9/4/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstanceCoordinator = SingleInstanceCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) {
        singleInstanceCoordinator.terminatePreviousInstances()
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct trackenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = UsageStore()

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
            systemImage: "gauge.with.dots.needle.67percent"
        ) {
            MenuBarView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
