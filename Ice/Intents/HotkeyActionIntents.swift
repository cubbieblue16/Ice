//
//  HotkeyActionIntents.swift
//  Ice
//

import AppIntents

// One intent per hotkey action. Each performs its action through
// `HotkeyAction.perform(appState:)`, the code path the hotkey takes,
// and none of them brings the app forward when run.

// MARK: - ToggleHiddenSectionIntent

/// Shows or hides the hidden section, like the hotkey of the same name.
struct ToggleHiddenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Hidden Section"

    static let description: IntentDescription? = IntentDescription(
        "Shows or hides the menu bar items in Ice's hidden section."
    )

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        HotkeyAction.toggleHiddenSection.perform(appState: appState)
        return .result()
    }
}

// MARK: - ToggleAlwaysHiddenSectionIntent

/// Shows or hides the always-hidden section, like the hotkey of the same name.
struct ToggleAlwaysHiddenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Always-Hidden Section"

    static let description: IntentDescription? = IntentDescription(
        "Shows or hides the menu bar items in Ice's always-hidden section."
    )

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        HotkeyAction.toggleAlwaysHiddenSection.perform(appState: appState)
        return .result()
    }
}

// MARK: - SearchMenuBarItemsIntent

/// Opens or closes the menu bar item search panel, like the hotkey of the same name.
struct SearchMenuBarItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Menu Bar Items"

    static let description: IntentDescription? = IntentDescription(
        "Opens or closes Ice's menu bar item search panel."
    )

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        HotkeyAction.searchMenuBarItems.perform(appState: appState)
        return .result()
    }
}

// MARK: - ToggleIceBarIntent

/// Turns the Ice Bar setting on or off, like the "Enable the Ice Bar" hotkey.
struct ToggleIceBarIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Ice Bar"

    static let description: IntentDescription? = IntentDescription(
        "Turns the Ice Bar on or off. The Ice Bar shows hidden menu bar items in a bar below the menu bar."
    )

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        HotkeyAction.enableIceBar.perform(appState: appState)
        return .result()
    }
}

// MARK: - ToggleApplicationMenusIntent

/// Hides or shows the application menus, like the hotkey of the same name.
struct ToggleApplicationMenusIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Application Menus"

    static let description: IntentDescription? = IntentDescription(
        "Hides or shows the menus of the frontmost application to make room for menu bar items."
    )

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        HotkeyAction.toggleApplicationMenus.perform(appState: appState)
        return .result()
    }
}
