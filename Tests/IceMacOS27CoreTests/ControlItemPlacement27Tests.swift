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

    @Test("Before macOS 27 the autosave name is unchanged")
    func earlierAutosaveName() {
        #expect(ControlItemPlacement.autosaveName(for: "Ice.ControlItem.Visible", generation: 7, isMacOS27: false)
            == "Ice.ControlItem.Visible")
    }

    @Test("On macOS 27 generation 0 and 1 both give .g1")
    func firstGenerationAutosaveName() {
        #expect(ControlItemPlacement.autosaveName(for: "Ice.ControlItem.Visible", generation: 0, isMacOS27: true)
            == "Ice.ControlItem.Visible.g1")
        #expect(ControlItemPlacement.autosaveName(for: "Ice.ControlItem.Visible", generation: 1, isMacOS27: true)
            == "Ice.ControlItem.Visible.g1")
    }

    @Test("On macOS 27 a later generation is suffixed as given")
    func laterGenerationAutosaveName() {
        #expect(ControlItemPlacement.autosaveName(for: "Ice.ControlItem.Hidden", generation: 7, isMacOS27: true)
            == "Ice.ControlItem.Hidden.g7")
    }

    @Test("Only /Applications is a supported install location")
    func installLocation() {
        #expect(InstallLocation27.isSupported(bundlePath: "/Applications/Ice 27.0.app"))
        #expect(!InstallLocation27.isSupported(bundlePath: "/Users/someone/Applications/Ice 27.0.app"))
        #expect(!InstallLocation27.isSupported(bundlePath: "/Applications"))
    }
}
