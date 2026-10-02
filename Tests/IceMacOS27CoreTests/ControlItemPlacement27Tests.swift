import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("ControlItemPlacement")
struct ControlItemPlacementTests {
    @Test("On macOS 27 no seeded position is 0, which MenuBarAgent reads as unset")
    func macOS27Seeds() {
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .visible, isMacOS27: true) == 1)
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .hidden, isMacOS27: true) == 2)
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .alwaysHidden, isMacOS27: true) == nil)
    }

    @Test("Before macOS 27 the seeds are unchanged")
    func earlierSeeds() {
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .visible, isMacOS27: false) == 0)
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .hidden, isMacOS27: false) == 1)
        #expect(ControlItemPlacement.defaultPreferredPosition(for: .alwaysHidden, isMacOS27: false) == nil)
    }

    @Test("Positions from an earlier Ice 27.0 build move off 0 and 1")
    func migratesOldPositions() {
        let moved = ControlItemPlacement.migratedPositions(visible: 0, hidden: 1)
        #expect(moved.visible == 1)
        #expect(moved.hidden == 2)
    }

    @Test("Positions the user dragged, and missing ones, are left alone")
    func keepsOtherPositions() {
        let dragged = ControlItemPlacement.migratedPositions(visible: 400, hidden: 7)
        #expect(dragged.visible == 400)
        #expect(dragged.hidden == 7)
        let none = ControlItemPlacement.migratedPositions(visible: nil, hidden: nil)
        #expect(none.visible == nil)
        #expect(none.hidden == nil)
    }

    @Test("Only /Applications is a supported install location")
    func installLocation() {
        #expect(InstallLocation27.isSupported(bundlePath: "/Applications/Ice 27.0.app"))
        #expect(!InstallLocation27.isSupported(bundlePath: "/Users/someone/Applications/Ice 27.0.app"))
        #expect(!InstallLocation27.isSupported(bundlePath: "/Applications"))
    }
}
