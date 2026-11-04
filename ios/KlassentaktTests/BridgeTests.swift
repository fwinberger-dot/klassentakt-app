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

final class FileTests: XCTestCase {
    func testTypes() {
        XCTAssertEqual(FileKinds.types(["pdf"]), [.pdf])
        XCTAssertEqual(FileKinds.types([]), [.pdf, .image])
        XCTAssertEqual(FileKinds.types(["unbekannt-xyz"]).isEmpty, false)
        XCTAssertTrue(FileKinds.types(["any"]).contains(.item))
    }

    func testMimeAndPreview() {
        XCTAssertEqual(FileKinds.mime(for: URL(fileURLWithPath: "/t/a.pdf")), "application/pdf")
        XCTAssertEqual(FileKinds.mime(for: URL(fileURLWithPath: "/t/a.jpg")), "image/jpeg")
        XCTAssertTrue(FileKinds.previewable(URL(fileURLWithPath: "/t/Wochenplan.pdf")))
        XCTAssertFalse(FileKinds.previewable(URL(fileURLWithPath: "/t/Termine.ics")))
    }

    func testShouldDownload() {
        XCTAssertTrue(FileKinds.shouldDownload(mime: "text/html", disposition: "attachment; filename=a.pdf", canShow: true))
        XCTAssertTrue(FileKinds.shouldDownload(mime: "text/calendar", disposition: nil, canShow: true))
        XCTAssertTrue(FileKinds.shouldDownload(mime: "application/x-foo", disposition: nil, canShow: false))
        XCTAssertFalse(FileKinds.shouldDownload(mime: "text/html", disposition: "inline", canShow: true))
    }

    func testReadFile() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Wochenplan Test.pdf")
        try Data("%PDF-1.4".utf8).write(to: u)
        let f = FileKinds.read(u)
        XCTAssertEqual(f?.name, "Wochenplan Test.pdf")
        XCTAssertEqual(f?.type, "application/pdf")
    }
}
