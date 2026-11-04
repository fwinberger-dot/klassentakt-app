import XCTest
import UIKit
@testable import Klassentakt

final class ShortcutTests: XCTestCase {
    func testCombinationsAreUnique() {
        let keys = ShellCommand.allCases.map { "\($0.modifiers.rawValue)-\($0.input)" }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testEveryCommandHasTitleAndModifier() {
        for c in ShellCommand.allCases {
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertTrue(c.modifiers.contains(.command), "\(c) ohne ⌘")
            XCTAssertEqual(ShellCommand(rawValue: c.rawValue), c)
        }
    }

    func testNoClashWithSystemShortcuts() {
        // ⌘H (Home), ⌘Space (Spotlight), ⌘Tab, ⌘Q (App beenden) gehören dem System.
        let reserved: Set<String> = ["h", " ", "\t", "q"]
        for c in ShellCommand.allCases where c.modifiers == .command {
            XCTAssertFalse(reserved.contains(c.input), "\(c)")
        }
    }

    func testScreenKeysMatchClassroomScreen() {
        XCTAssertEqual(ShellCommand.phaseNext.screenKey, "ArrowRight")
        XCTAssertEqual(ShellCommand.timerToggle.screenKey, " ")
        XCTAssertTrue(MainViewController.keyJS(" ").contains("key: ' '"))
        XCTAssertTrue(MainViewController.keyJS("ArrowLeft").contains("'ArrowLeft'"))
    }

    func testCSSColor() {
        XCTAssertNotNil(MainViewController.color(fromCSS: "rgb(16, 34, 29)"))
        XCTAssertNil(MainViewController.color(fromCSS: "rgba(0, 0, 0, 0)"))
        XCTAssertNil(MainViewController.color(fromCSS: "transparent"))
    }
}
