//
//  ItemFallbackIcon27.swift
//  Ice
//

import AppKit

/// An application's icon, drawn as a stand-in for the image of its menu bar item.
///
/// On macOS 27 an item that is concealed is never drawn, so it cannot be photographed
/// (see ``ItemImageStore27``): one that was concealed before Ice ever saw it drawn has no
/// stored image. The Ice Bar and the layout editor draw the icon of the application that
/// owns the item instead, so the item can still be recognised and clicked.
@available(macOS 27.0, *)
@MainActor
enum ItemFallbackIcon27 {
    /// The height the icon is drawn at, in points, about that of a glyph on the menu bar.
    static let iconHeight: CGFloat = 18

    /// The height of the tile when the item's own height says nothing, as a menu bar's.
    private static let defaultTileHeight: CGFloat = 24

    /// Tiles already drawn, keyed by the application's bundle identifier and the tile's height.
    private static var tiles = [String: NSImage]()

    /// The tile for the item: the icon of the application that owns it, scaled to
    /// ``iconHeight`` with its aspect kept and centred vertically, with the same horizontal
    /// margin as the stored images (``ItemImageStore27/glyphMargin``).
    ///
    /// Returns `nil` for an item with no source application, or one whose application has
    /// no icon, and for Ice's own items.
    static func tile(for item: MenuBarItem) -> NSImage? {
        guard !item.isControlItem, let application = item.sourceApplication else {
            return nil
        }
        let height = item.bounds.height >= iconHeight ? item.bounds.height : defaultTileHeight
        let key = "\(application.bundleIdentifier ?? "pid-\(application.processIdentifier)")@\(height)"
        if let tile = tiles[key] {
            return tile
        }
        guard let icon = icon(of: application), icon.size.width > 0, icon.size.height > 0 else {
            return nil
        }
        let iconWidth = (iconHeight * icon.size.width / icon.size.height).rounded()
        let margin = ItemImageStore27.glyphMargin
        let size = CGSize(width: iconWidth + margin * 2, height: height)
        let iconRect = CGRect(x: margin, y: (height - iconHeight) / 2, width: iconWidth, height: iconHeight)
        let tile = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: iconRect)
            return true
        }
        tiles[key] = tile
        return tile
    }

    /// The icon of the application, from the running application or else from its bundle.
    private static func icon(of application: NSRunningApplication) -> NSImage? {
        if let icon = application.icon {
            return icon
        }
        guard let bundlePath = application.bundleURL?.path else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundlePath)
    }
}
