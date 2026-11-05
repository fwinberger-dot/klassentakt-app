import XCTest
import UIKit
@testable import Klassentakt

final class BeamerTests: XCTestCase {
    func testFitKeepsAspect() {
        // Beamer 16:9 auf iPad 4:3 → Breite füllt, oben/unten Rand
        XCTAssertEqual(LiveMirror.fit(CGSize(width: 1920, height: 1080), into: CGSize(width: 1180, height: 820)), 1180.0 / 1920, accuracy: 0.0001)
        // iPad 4:3 auf Beamer 16:9 → Höhe füllt, links/rechts Rand
        XCTAssertEqual(LiveMirror.fit(CGSize(width: 1180, height: 820), into: CGSize(width: 1920, height: 1080)), 1080.0 / 820, accuracy: 0.0001)
        XCTAssertEqual(LiveMirror.fit(.zero, into: CGSize(width: 10, height: 10)), 1)
    }

    func testModeNamesForWeb() {
        XCTAssertEqual(BeamerMode.extend.rawValue, "erweitern")
        XCTAssertEqual(BeamerMode.mirror.rawValue, "spiegeln")
        XCTAssertEqual(BeamerMode(rawValue: "spiegeln"), .mirror)
    }

    func testStartsExtendedWithoutScreen() {
        let st = Beamer.shared.stateForWeb
        XCTAssertEqual(st["mode"] as? String, "erweitern")
        XCTAssertEqual(st["steuern"] as? Bool, false)
        XCTAssertEqual(st["open"] as? Bool, false)
    }

    func testModeControl() {
        var got: BeamerMode?
        let c = BeamerMode.control(.extend, id: "x") { got = $0 }
        XCTAssertEqual(c.numberOfSegments, 2)
        XCTAssertEqual(c.titleForSegment(at: 1), "Spiegeln")
        c.selectedSegmentIndex = 1
        c.sendActions(for: .valueChanged)
        XCTAssertEqual(got, .mirror)
    }
}
