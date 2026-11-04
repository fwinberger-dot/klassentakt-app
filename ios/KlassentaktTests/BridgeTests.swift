import XCTest
@testable import Klassentakt

final class BridgeTests: XCTestCase {
    func testParseValid() {
        let m = Shell.parse(["type": "send", "name": "scan", "payload": ["format": "pdf"]])
        XCTAssertEqual(m?.kind, .send)
        XCTAssertEqual(m?.name, "scan")
        XCTAssertEqual(m?.payload["format"] as? String, "pdf")
    }

    func testParseRejectsJunk() {
        XCTAssertNil(Shell.parse("hallo"))
        XCTAssertNil(Shell.parse(["type": "boom", "name": "x"]))
        XCTAssertNil(Shell.parse(["type": "send", "name": ""]))
        XCTAssertNil(Shell.parse(["type": "send", "name": String(repeating: "a", count: 65)]))
    }

    func testParseMissingPayloadIsEmpty() {
        XCTAssertEqual(Shell.parse(["type": "listen", "name": "file"])?.payload.count, 0)
    }

    func testTrustedHosts() {
        XCTAssertTrue(Shell.trusted("klassentakt.ch"))
        XCTAssertTrue(Shell.trusted("staging.klassentakt.ch"))
        XCTAssertFalse(Shell.trusted("klassentakt.ch.evil.com"))
        XCTAssertFalse(Shell.trusted("youtube.com"))
    }

    func testChunksRoundTrip() {
        let s = String(repeating: "abcdefgh", count: 1000)
        let c = Shell.chunks(s, size: 777)
        XCTAssertEqual(c.joined(), s)
        XCTAssertTrue(c.dropLast().allSatisfy { $0.count == 777 })
        XCTAssertEqual(Shell.chunks(""), [""])
    }

    func testEmitJSEscapes() {
        let js = Shell.emitJS("x'); alert(1); ('", ["t": "a\"b"])!
        XCTAssertTrue(js.contains("[\"x'); alert(1); ('\"][0]"))
        XCTAssertTrue(js.contains("\\\"b"))
    }

    func testListenerRegistry() {
        let shell = Shell()
        XCTAssertFalse(shell.isListening("file"))
        XCTAssertFalse(shell.emit("file"))
    }
}
