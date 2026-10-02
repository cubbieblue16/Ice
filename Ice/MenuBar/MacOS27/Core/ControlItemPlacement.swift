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

    /// Moves positions stored by an earlier Ice 27.0 build out of the "unset" value.
    ///
    /// The visible item's 0 becomes 1, and the hidden divider's 1 becomes 2 so the icon stays to
    /// the right of the divider. Positions the user has dragged to any other value are returned
    /// unchanged.
    static func migratedPositions(visible: CGFloat?, hidden: CGFloat?) -> (visible: CGFloat?, hidden: CGFloat?) {
        (visible == 0 ? 1 : visible, hidden == 1 ? 2 : hidden)
    }
}
