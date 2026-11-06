import XCTest

/// Screenshots und Videos pro Funktion für die Abnahme (Workflow «Klassentakt-shots-paketA").
/// Die App läuft im Test-Modus: Test-Arbeitsblatt statt Kamera, Beamer als Vorschau oben links, nur erfundene Daten.
final class ShotsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-ktUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"] + args
        app.launch()
        pause(3)
    }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["KT_SHOTS"] {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func pause(_ s: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: s) }

    @discardableResult
    private func tap(_ e: XCUIElement, wait: TimeInterval = 8) -> Bool {
        guard e.waitForExistence(timeout: wait) else { return false }
        e.tap()
        pause()
        return true
    }

    // 4 – Tastatur-Kürzel
    func test4Kuerzel() {
        launch(["-ktRun", "shortcuts"])
        XCTAssertTrue(app.navigationBars["Tastatur-Kürzel"].waitForExistence(timeout: 40))
        pause()
        shot("4-kuerzel-1-uebersicht")
        app.terminate()
        launch(["-ktRun", "tool-timer"])
        _ = app.staticTexts["Zuerst den Classroom Screen öffnen (⌘⇧B)"].waitForExistence(timeout: 40)
        shot("4-kuerzel-2-timer-ohne-screen")
    }

    // 3 – Scanner
    func test3Scanner() {
        launch(["-ktRun", "scan"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        pause()
        shot("3-scanner-1-format-waehlen")
        tap(app.alerts.buttons["Als ein PDF"])
        pause(3)
        shot("3-scanner-2-pdf-vorschau")
    }

    // 1 – Dokumentenkamera
    func test1Kamera() {
        launch(["-ktBeamerPreview", "-ktRun", "camera"])
        let preview = app.otherElements["camPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        pause(2)
        shot("1-kamera-1-live-auf-beamer")
        preview.pinch(withScale: 2.2, velocity: 1.5)
        pause()
        tap(app.buttons["camRotate"])
        shot("1-kamera-2-zoom-und-gedreht")
        tap(app.buttons["camFreeze"])
        tap(app.buttons["camTorch"])
        shot("1-kamera-3-standbild-licht")
        tap(app.buttons["camPhoto"])
        pause(3)
        shot("1-kamera-4-foto-uebernehmen")
        // Anhang: Kamera startet als Foto, Umschalter Foto | Scannen
        app.terminate()
        launch(["-ktRun", "web-open-camera-foto"])
        XCTAssertTrue(app.segmentedControls["camMode"].waitForExistence(timeout: 40))
        pause(2)
        shot("1-kamera-5-anhang-foto-modus")
        tap(app.buttons["camPhoto"])
        pause(3)
        shot("1-kamera-6-anhang-foto-ausgeloest")
        app.terminate()
        launch(["-ktRun", "web-open-camera-foto"])
        XCTAssertTrue(app.segmentedControls["camMode"].waitForExistence(timeout: 40))
        tap(app.segmentedControls["camMode"].buttons["Scannen"])
        pause(4)
        shot("1-kamera-7-anhang-scannen")
    }

    // 2 – Beamer: Erweitern mit Bild im Bild, Steuern auf dem iPad, Spiegeln; Kamera als Werkzeug
    func test2Beamer() {
        launch(["-ktBeamerPreview", "-ktRun", "screen-toggle"])
        let live = app.descendants(matching: .any)["pipLive"]
        XCTAssertTrue(live.waitForExistence(timeout: 30))
        pause(5)
        shot("2-beamer-1-erweitern-bild-im-bild")
        tap(live)
        pause(2)
        shot("2-beamer-2-steuern-auf-ipad")
        tap(app.segmentedControls["screenMode"].buttons["Spiegeln"])
        pause(2)
        shot("2-beamer-3-spiegeln")
        tap(app.buttons["screenToPlanner"])
        pause(2)
        shot("2-beamer-4-spiegeln-planer")
        tap(app.segmentedControls["pipMode"].buttons["Erweitern"])
        pause(4)
        shot("2-beamer-5-wieder-erweitern")
        app.terminate()
        launch(["-ktBeamerPreview", "-ktRun", "web-open-camera"])
        XCTAssertTrue(app.otherElements["camPreview"].waitForExistence(timeout: 30))
        pause(2)
        shot("2-beamer-6-kamera-aus-werkzeugkoffer")
        tap(app.buttons["camClose"])
        app.terminate()
        launch(["-ktBeamerPreview", "-ktRun", "demo-editing"])
        XCTAssertTrue(app.descendants(matching: .any)["screenBar"].waitForExistence(timeout: 40))
        pause(4)
        shot("2-beamer-7-bearbeiten-beamer-steht")
        app.terminate()
        launch(["-ktBeamerPreview", "-ktRun", "web-open-camera-live"])
        XCTAssertTrue(app.otherElements["camPreview"].waitForExistence(timeout: 30))
        pause(2)
        XCTAssertFalse(app.buttons["camPhoto"].exists)
        shot("2-beamer-8-visualizer-ohne-foto")
    }

    // Runde 5 – Bild im Bild im Unterricht: Woche im Planer, Screen steuern, zurück. Erfundene Klasse (-ktDemoKlasse).
    // Pro Schritt zwei Bilder: «-beamer» mit Vorschau (oben links ausgeschnitten = Beamer), «-ipad» ohne Vorschau.
    func test6Runde5() {
        launch(["-ktBeamerPreview", "-ktDemoKlasse"])
        let live = app.descendants(matching: .any)["pipLive"]
        XCTAssertTrue(live.waitForExistence(timeout: 60))
        // Der CI-Simulator ist langsam: erst weiter, wenn die Woche wirklich dasteht.
        XCTAssertTrue(webText("KW").waitForExistence(timeout: 180))
        pause(4)
        // Screen öffnen (kommt gross aufs iPad) und zurück zum Planer: Screen läuft am Beamer.
        tap(live)
        XCTAssertTrue(app.buttons["screenToPlanner"].waitForExistence(timeout: 30))
        pause(6)
        tap(app.buttons["screenToPlanner"])
        _ = webText("KW").waitForExistence(timeout: 60)
        pause(8)
        pair("r5-1-woche-bild-im-bild")
        tap(live)
        XCTAssertTrue(app.buttons["screenToPlanner"].waitForExistence(timeout: 10))
        XCTAssertTrue(webText("November").waitForExistence(timeout: 120))
        pause(5)
        pair("r5-2-steuern-auf-ipad")
        tap(app.buttons["ktTimer"])          // wie ⌘⇧T
        pause(5)
        pair("r5-3-timer-live")
        tap(app.buttons["ktPhase"])          // wie ⌥⌘→
        pause(4)
        pair("r5-4-phase-weiter")
        tap(app.buttons["ktEditToggle"])
        pause(3)
        pair("r5-5-bearbeiten-beamer-steht")
        tap(app.buttons["ktEditToggle"])
        pause(3)
        tap(app.buttons["screenToPlanner"])
        _ = webText("KW").waitForExistence(timeout: 60)
        pause(6)
        pair("r5-6-zurueck-in-der-woche")
        // Bild im Bild grösser ziehen (Griff oben links), dann mit «–» ausblenden und über den Griff zurückholen.
        let grip = app.descendants(matching: .any)["pipResize"]
        if grip.waitForExistence(timeout: 5) {
            grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.3)))
            pause(3)
            pair("r5-7-bild-im-bild-gross")
        }
        tap(app.buttons["pipHide"])
        pause(2)
        pair("r5-8-ausgeblendet-griff")
        tap(app.buttons["pipHandle"])
        pause(3)
        pair("r5-9-wieder-da")
    }

    private func webText(_ t: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }

    private func pair(_ name: String) {
        tap(app.buttons["ktPreviewShow"])
        shot(name + "-beamer")
        tap(app.buttons["ktPreviewHide"])
        pause(0.8)
        shot(name + "-ipad")
        tap(app.buttons["ktPreviewShow"])
    }

    // 5 – Teilen-Menü und Dateien
    func test5Dateien() {
        launch(["-ktRun", "demo-export"])
        pause(3)
        shot("5-dateien-1-export-vorschau")
        if tap(app.buttons["previewShare"], wait: 4) {
            pause(2)
            shot("5-dateien-2-teilen-menue")
        }
        app.terminate()
        launch(["-ktRun", "demo-ics"])
        pause(3)
        shot("5-dateien-3-kalender-teilen")
        app.terminate()
        launch(["-ktRun", "import"])
        pause(4)
        shot("5-dateien-4-import-aus-dateien")
    }
}
