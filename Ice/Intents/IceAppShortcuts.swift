//
//  IceAppShortcuts.swift
//  Ice
//

import AppIntents

/// The App Shortcuts that Ice offers to Shortcuts, Spotlight and Siri.
struct IceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleHiddenSectionIntent(),
            phrases: [
                "Toggle hidden items in \(.applicationName)",
                "Toggle the hidden section in \(.applicationName)",
            ],
            shortTitle: "Toggle Hidden Items",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: ToggleAlwaysHiddenSectionIntent(),
            phrases: [
                "Toggle always-hidden items in \(.applicationName)",
                "Toggle the always-hidden section in \(.applicationName)",
            ],
            shortTitle: "Toggle Always-Hidden Items",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: SearchMenuBarItemsIntent(),
            phrases: [
                "Search menu bar items in \(.applicationName)",
                "Search the menu bar with \(.applicationName)",
            ],
            shortTitle: "Search Menu Bar Items",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: ToggleIceBarIntent(),
            phrases: [
                "Toggle the \(.applicationName) Bar",
                "Turn the \(.applicationName) Bar on or off",
            ],
            shortTitle: "Toggle Ice Bar",
            systemImageName: "menubar.arrow.down.rectangle"
        )
        AppShortcut(
            intent: ToggleApplicationMenusIntent(),
            phrases: [
                "Toggle application menus with \(.applicationName)",
                "Toggle app menus with \(.applicationName)",
            ],
            shortTitle: "Toggle App Menus",
            systemImageName: "filemenu.and.selection"
        )
    }
}
