//
//  MenuBarItemService.swift
//  Shared
//

import Foundation

enum MenuBarItemService {
    static let name = "tech.kuta.Ice27.MenuBarItemService"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
        /// Activates an assessment-mode assertion that keeps only these bundle
        /// identifiers on the menu bar (macOS 27 and later).
        case activateConcealment(allowedBundleIDs: [String])
        /// Releases the assertion with this identifier (macOS 27 and later).
        case invalidateConcealment(id: UInt64)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
        /// The identifier of the assertion that is now live.
        case concealmentActivated(id: UInt64)
        /// Why the assertion could not be activated, in human readable form.
        case concealmentFailed(reason: String)
        /// The assertion was released, or was not live.
        case concealmentInvalidated
    }
}
