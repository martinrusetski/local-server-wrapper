//
//  UpdaterController.swift
//  LocalServerWrapper
//
//  Wraps Sparkle's SPUStandardUpdaterController so the app can check for and
//  install updates from the appcast feed declared in Info.plist (SUFeedURL +
//  SUPublicEDKey). The controller is created once at launch and drives both the
//  automatic background checks and the manual "Check for Updates…" menu item.
//

import SwiftUI
import Combine
import Sparkle

/// Owns the Sparkle updater for the app's lifetime and exposes just enough for
/// the SwiftUI menu command to bind to.
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// True while Sparkle considers a manual check permissible (it briefly isn't
    /// mid-check). Bound to the menu item's disabled state.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true begins the scheduled-check timer immediately.
        // No custom delegate is needed for the standard flow.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers the user-initiated update check (shows Sparkle's UI, including a
    /// "you're up to date" panel when there's nothing new).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// A reusable "Check for Updates…" menu item that disables itself while a check
/// is already in flight.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
