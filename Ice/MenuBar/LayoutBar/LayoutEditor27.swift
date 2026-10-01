//
//  LayoutEditor27.swift
//  Ice
//

import SwiftUI

/// The menu bar layout editor on macOS 27.
///
/// macOS orders the items on the bar itself, so the editor only moves an application
/// between the three sections. Each section is a horizontal collection in one SwiftUI
/// reorderable container. Dropping an item in another section saves its application
/// there, the same way a drop on the AppKit editor, which is still used below macOS 27,
/// does.
@available(macOS 27.0, *)
struct LayoutEditor27: View {
    /// A menu bar item as the editor shows it.
    private struct LayoutTile: Identifiable {
        let item: MenuBarItem
        var section: MacOS27Section
        let bundleID: String?
        let displayName: String
        let toolTip: String

        /// Whether the item is drawn as available, as `LayoutBarItemView.isEnabled`.
        let isEnabled: Bool

        /// Whether the process that owns the item is unresponsive. The AppKit editor
        /// refuses to drag such an item.
        let isUnresponsive: Bool

        var id: CGWindowID {
            item.windowID
        }

        /// Whether the item can be dragged to another section.
        ///
        /// A drop on the AppKit editor ignores Ice's own item, so it cannot be lifted here.
        var canMove: Bool {
            isEnabled && !isUnresponsive && !item.isControlItem && bundleID != nil
        }

        init(item: MenuBarItem, section: MacOS27Section, bundleID: String?) {
            let displayName = item.displayName
            var isEnabled = item.isMovable
            var toolTip = displayName
            // The same rules and wording as `LayoutBarItemView` on macOS 27.
            if !item.isControlItem {
                if !item.canBeHidden {
                    isEnabled = false
                    toolTip = "\(displayName) — macOS always shows this item"
                } else if bundleID == nil {
                    isEnabled = false
                    toolTip = "\(displayName) — cannot be hidden on this version of macOS"
                }
            }
            self.item = item
            self.section = section
            self.bundleID = bundleID
            self.displayName = displayName
            self.toolTip = toolTip
            self.isEnabled = isEnabled
            self.isUnresponsive = Bridging.isProcessUnresponsive(item.ownerPID)
        }
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache

    /// Sections chosen in the editor that the item cache has yet to catch up with,
    /// keyed by bundle identifier.
    ///
    /// The cache is rebuilt after the saved layout changes, which reads every item
    /// through Accessibility. Until then a dropped item would jump back to where it
    /// came from.
    @State private var pendingSections = [String: MacOS27Section]()

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        let tiles = currentTiles()
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { name in
                layoutBar(for: name, tiles: tiles[MacOS27Section(name)] ?? [])
            }
        }
        .reorderContainer(for: LayoutTile.self, in: MacOS27Section.self) { difference in
            move(difference)
        }
        .onChange(of: itemManager.itemCache) {
            pendingSections.removeAll()
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name, tiles: [LayoutTile]) -> some View {
        if isSectionEnabled(name) {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                barContent(for: name, tiles: tiles)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .menuBarItemContainer(appState: appState)
                    .containerShape(backgroundShape)
                    .clipShape(backgroundShape)
                    .contentShape([.interaction, .focusEffect], backgroundShape)
                    .overlay {
                        backgroundShape
                            .strokeBorder(.quaternary)
                    }
            }
        }
    }

    @ViewBuilder
    private func barContent(for name: MenuBarSection.Name, tiles: [LayoutTile]) -> some View {
        if imageCache.cacheFailed(for: name) {
            Text("Unable to display menu bar items")
                .font(.body)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    // Items that cannot change section stay out of the reorderable
                    // collection, so they cannot be lifted at all.
                    ForEach(tiles.filter { !$0.canMove }) { tile in
                        tileView(tile)
                    }
                    ForEach(tiles.filter(\.canMove)) { tile in
                        tileView(tile)
                            .contextMenu {
                                moveMenu(for: tile)
                            }
                    }
                    .reorderable(collectionID: MacOS27Section(name))
                }
                .padding(.horizontal, 7.5)
                .frame(maxHeight: .infinity)
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    private func tileView(_ tile: LayoutTile) -> some View {
        Image(nsImage: imageCache.images[tile.item.tag]?.nsImage ?? NSImage(size: tile.item.bounds.size))
            // Lets Scripts/macos27/verify-layout.sh find the item.
            .accessibilityLabel(tile.displayName)
            .opacity(tile.isEnabled ? 1 : 0.67)
            .overlay(alignment: .bottomTrailing) {
                if tile.isUnresponsive {
                    Image(nsImage: .warning)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .help(tile.toolTip)
    }

    /// Moves the item's application without dragging, which also reaches a section
    /// that has no items to drop beside.
    @ViewBuilder
    private func moveMenu(for tile: LayoutTile) -> some View {
        if let bundleID = tile.bundleID {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { name in
                if MacOS27Section(name) != tile.section, isSectionEnabled(name) {
                    Button("Move to \(name.displayString) Section") {
                        moveApplication(bundleID, to: MacOS27Section(name))
                    }
                }
            }
        }
    }

    private func isSectionEnabled(_ name: MenuBarSection.Name) -> Bool {
        appState.menuBarManager.section(withName: name)?.isEnabled == true
    }

    /// The items in each section, in the cache's order, with the sections chosen in
    /// the editor applied. Items still on their way to a section come last.
    private func currentTiles() -> [MacOS27Section: [LayoutTile]] {
        let cache = itemManager.itemCache
        let bundleIDs = MenuBarItem.sourceBundleIDs(of: cache.managedItems)
        var staying = [MacOS27Section: [LayoutTile]]()
        var arriving = [MacOS27Section: [LayoutTile]]()
        for name in MenuBarSection.Name.allCases {
            let cachedSection = MacOS27Section(name)
            for item in cache[name] {
                var tile = LayoutTile(
                    item: item,
                    section: cachedSection,
                    bundleID: item.sourcePID.flatMap { bundleIDs[$0] }
                )
                if
                    tile.canMove,
                    let bundleID = tile.bundleID,
                    let pending = pendingSections[bundleID],
                    pending != cachedSection
                {
                    tile.section = pending
                    arriving[pending, default: []].append(tile)
                } else {
                    staying[cachedSection, default: []].append(tile)
                }
            }
        }
        return staying.merging(arriving, uniquingKeysWith: +)
    }

    /// Applies a drop: every lifted item that may change section moves its application
    /// to the destination. macOS orders the items within a section, so the position in
    /// the destination is not used.
    private func move(_ difference: ReorderDifference<CGWindowID, MacOS27Section>) {
        let destination = difference.destination.collectionID
        let tiles = currentTiles().values.joined()
        var movedBundleIDs = Set<String>()
        for windowID in difference.sources {
            guard
                let tile = tiles.first(where: { $0.id == windowID }),
                tile.canMove,
                tile.section != destination,
                let bundleID = tile.bundleID,
                movedBundleIDs.insert(bundleID).inserted
            else {
                continue
            }
            moveApplication(bundleID, to: destination)
        }
    }

    /// Saves the application's section the same way a drop on the AppKit editor does.
    private func moveApplication(_ bundleID: String, to section: MacOS27Section) {
        pendingSections[bundleID] = section
        appState.concealer27.setSection(section, for: bundleID)
    }
}
