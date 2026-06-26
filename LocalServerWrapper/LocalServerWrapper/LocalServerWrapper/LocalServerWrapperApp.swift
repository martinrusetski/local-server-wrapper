//
//  LocalServerWrapperApp.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct LocalServerWrapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var configurationManager = ConfigurationManager()

    var body: some Scene {
        WindowGroup {
            ContentView(configurationManager: configurationManager)
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(configurationManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// userInfo key carrying the generated bundle's path on success notifications
    static let bundlePathUserInfoKey = "bundlePath"

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even while the app is in the foreground (it usually is right after generating).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Reveal the generated bundle in Finder when the user clicks the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let path = response.notification.request.content.userInfo[Self.bundlePathUserInfoKey] as? String
        else { return }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
