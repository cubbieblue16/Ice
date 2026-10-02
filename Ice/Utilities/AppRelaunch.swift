//
//  AppRelaunch.swift
//  Ice
//

import AppKit
import OSLog

/// A namespace for relaunching Ice itself.
@MainActor
enum AppRelaunch {
    private static let logger = Logger(category: "AppRelaunch")

    /// Starts a new instance of Ice, then terminates this one once the new instance has launched.
    ///
    /// If the new instance cannot be launched, the error is logged and this instance keeps running.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if let error {
                    logger.error("Failed to relaunch: \(error.localizedDescription, privacy: .public)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
