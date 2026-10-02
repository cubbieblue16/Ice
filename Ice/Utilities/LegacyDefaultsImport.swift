//
//  LegacyDefaultsImport.swift
//  Ice
//

import Foundation
import OSLog

/// Copies the settings of the previous `com.jordanbaird.Ice` app into this app's
/// defaults domain, once, so that renaming the fork does not reset anything.
enum LegacyDefaultsImport {
    /// The defaults domain of the app this fork used to share an identity with.
    static let legacyDomain = "com.jordanbaird.Ice"

    /// A key that only a configured copy of this app has.
    static let layoutKey = "MacOS27Layout"

    /// Set once the import has run (or was found to be unnecessary).
    static let markerKey = "Ice27DidImportLegacyDefaults"

    /// Key prefixes that belong to the system, to Sparkle or to the old app's
    /// window state, not to Ice's settings.
    static let skippedPrefixes = ["NS", "Apple", "SU", "com.apple"]

    private static let logger = Logger(category: "LegacyDefaultsImport")

    /// Imports the legacy settings if this app has none of its own yet.
    ///
    /// Call this before anything reads from `UserDefaults.standard`.
    static func importIfNeeded(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: markerKey) else {
            return
        }
        defer {
            defaults.set(true, forKey: markerKey)
        }
        guard defaults.object(forKey: layoutKey) == nil else {
            return
        }
        guard
            let legacy = defaults.persistentDomain(forName: legacyDomain),
            !legacy.isEmpty
        else {
            return
        }
        var count = 0
        for (key, value) in legacy where !skippedPrefixes.contains(where: key.hasPrefix) {
            defaults.set(value, forKey: key)
            count += 1
        }
        logger.info("Imported \(count, privacy: .public) settings from the previous Ice")
    }
}
