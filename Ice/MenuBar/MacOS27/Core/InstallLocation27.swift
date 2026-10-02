//
//  InstallLocation27.swift
//  Ice
//

/// Where Ice has to be installed for macOS 27 to identify its menu bar items.
///
/// MenuBarAgent resolves a client's bundle identity only for applications under `/Applications`.
/// Outside it the item is hosted with no identity, so the per-application allowlist and the saved
/// layout cannot address it.
enum InstallLocation27 {
    /// Whether an application bundle at the given path is where macOS 27 can identify it.
    static func isSupported(bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Applications/")
    }
}
