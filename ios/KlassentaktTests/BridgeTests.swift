import XCTest
@testable import Klassentakt

final class BridgeTests: XCTestCase {
    func testFeaturesFollowTheDevice() {
        XCTAssertFalse(Shell.features(camera: true, scan: true).contains("beamer-layer"))
        XCTAssertTrue(Shell.features(camera: true, scan: true).contains("camera"))
        XCTAssertFalse(Shell.features(camera: false, scan: true).contains("camera"))
        XCTAssertTrue(Shell.features(camera: true, scan: true).contains("camera-capture"))
        XCTAssertTrue(Shell.features(camera: false, scan: false).contains("display-state"))
        XCTAssertFalse(Shell.features(camera: false, scan: true).contains("camera-capture"))
        XCTAssertFalse(Shell.features(camera: true, scan: false).contains("scan"))
        XCTAssertTrue(Shell.features(camera: false, scan: false).contains("files"))
        XCTAssertTrue(Shell.features(camera: false, scan: false).contains("editing"))
    }

    func testServerOnlyKlassentakt() {
        XCTAssertEqual(MainViewController.serverName(nil), "klassentakt.ch")
        XCTAssertEqual(MainViewController.serverName("staging.klassentakt.ch"), "staging.klassentakt.ch")
        XCTAssertEqual(MainViewController.serverName(" Staging.Klassentakt.ch "), "staging.klassentakt.ch")
        XCTAssertEqual(MainViewController.serverName("evil.example.com"), "klassentakt.ch")
        XCTAssertEqual(MainViewController.serverName("klassentakt.ch.evil.com"), "klassentakt.ch")
        XCTAssertEqual(MainViewController.serverName("a/b.klassentakt.ch"), "klassentakt.ch")
        XCTAssertEqual(MainViewController.server, "klassentakt.ch") // Standard-Build
        XCTAssertNil(MainViewController.testBandText("klassentakt.ch"))
        XCTAssertEqual(MainViewController.testBandText("staging.klassentakt.ch"), "TEST · staging")
    }

    func testRefIsShortenedAndOptional() {
        XCTAssertNil(MainViewController.ref([:]))
        XCTAssertNil(MainViewController.ref(["ref": ""]))
        XCTAssertEqual(MainViewController.ref(["ref": "lektion-42"]), "lektion-42")
        XCTAssertEqual(MainViewController.ref(["ref": String(repeating: "x", count: 500)])?.count, 200)
    }

    func testFileScriptPassesRef() {
        XCTAssertTrue(Shell.script(version: "1").source.contains("ref: meta.ref"))
    }

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
