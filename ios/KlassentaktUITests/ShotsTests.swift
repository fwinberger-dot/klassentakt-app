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
