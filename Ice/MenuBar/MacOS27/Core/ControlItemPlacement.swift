//
//  ControlItemPlacement.swift
//  Ice
//

import CoreGraphics

/// Where Ice asks macOS to place its control items, expressed as the legacy
/// `NSStatusItem Preferred Position <autosaveName>` values.
///
/// On macOS 27 MenuBarAgent places a newly seen status item from that legacy value (a smaller
/// value is further right, as in classic AppKit), except that exactly 0 counts as "unset" and
/// gets the default placement: the leftmost trailing slot. When the bar cannot hold every item,
/// the leftmost third-party items are folded into the system overflow group behind the "«"
/// chevron, so an item seeded at 0 ends up inside it (measured on macOS 27.0, 2026-10-02, a
/// notched 14-inch display: 0 landed at x=876, inside the group; 1 and 2 landed at x=1261).
///
/// MenuBarAgent reads that legacy value only the first time it sees the key
/// `status:<bundleID>::<autosaveName>`. It logs `Using legacy NSStatusItemHost preferredPosition`
/// for about ten seconds, then persists the placement to its own store (the `com.apple.MenuBar`
/// preferences, kept in a data vault that even the user cannot read). After that the key is known,
/// and the legacy value is ignored, even across restarts of the agent. Changing the stored seeds
/// cannot move an item whose key is known, so the only way to be placed again is a new autosave
/// name, which `autosaveName(for:generation:isMacOS27:)` builds from a generation counter.
enum ControlItemPlacement {
    /// A control item, independent of `ControlItem.Identifier`.
    enum Slot {
        case visible
        case hidden
        case alwaysHidden
    }

    /// The position to seed for a control item that has none stored, or `nil` to leave it unset.
    ///
    /// Before macOS 27 the visible item takes 0 and the hidden divider 1, which puts both ahead
    /// of the existing items. On 27 they take 1 and 2 instead, so neither is mistaken for unset.
    static func defaultPreferredPosition(for slot: Slot, isMacOS27: Bool) -> CGFloat? {
        switch slot {
        case .visible: isMacOS27 ? 1 : 0
        case .hidden: isMacOS27 ? 2 : 1
        case .alwaysHidden: nil
        }
    }

    /// The autosave name for a control item's status item.
    ///
    /// Before macOS 27 this is `base`. On 27 it carries a generation suffix, and a generation below
    /// 1 (an absent setting) counts as 1. Raising the generation gives the item a key MenuBarAgent
    /// has never seen, so it is placed again from the legacy position.
    static func autosaveName(for base: String, generation: Int, isMacOS27: Bool) -> String {
        isMacOS27 ? "\(base).g\(max(generation, 1))" : base
    }
}
