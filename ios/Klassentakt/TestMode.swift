import UIKit
import WebKit

/// UI-Test-Modus für Screenshots und Videos (Workflow «Klassentakt-shots-paketA").
/// Nur in Debug-Builds und nur mit dem Launch-Argument `-ktUITest`. Im Release ist `on` immer false.
/// - Kamera und Scanner nehmen ein erfundenes Test-Arbeitsblatt statt der Kamera.
/// - `-ktBeamerPreview`: zeigt den Beamer verkleinert oben links (der Simulator hat keinen externen Bildschirm).
/// - `-ktRun <befehl>`: führt nach dem Start einen Befehl aus (ShellCommand, Demo oder `web-open-camera`).
/// - `-ktDemoKlasse`: Web-App als lokaler Prototyp mit ihrer Demo-Woche (über `DemoScheme`), alle Namen erfunden.
enum TestMode {
    static var on: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ktUITest")
        #else
        return false
        #endif
    }
    static var beamerPreview: Bool { on && ProcessInfo.processInfo.arguments.contains("-ktBeamerPreview") }
    static var demoClass: Bool { on && ProcessInfo.processInfo.arguments.contains("-ktDemoKlasse") }

    static var run: String? {
        guard on else { return nil }
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-ktRun"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// Erfundenes Arbeitsblatt (keine echten Klassen oder Kinder).
    static func worksheet(page: Int = 1, size: CGSize = CGSize(width: 1240, height: 1754)) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let w = size.width
            func text(_ s: String, _ y: CGFloat, _ font: UIFont, _ color: UIColor = .black) {
                (s as NSString).draw(at: CGPoint(x: 90, y: y), withAttributes: [.font: font, .foregroundColor: color])
            }
            text("Arbeitsblatt Brüche – Seite \(page)", 90, .boldSystemFont(ofSize: 64))
            text("Name: Mia Muster        Klasse 5x (Beispiel)", 190, .systemFont(ofSize: 36), .darkGray)
            let tasks = ["1)  ½ + ¼ = ____", "2)  ⅔ von 12 = ____", "3)  Färbe ¾ des Kreises.", "4)  Ordne: ⅓, ½, ⅙"]
            for (i, t) in tasks.enumerated() { text(t, 320 + CGFloat(i) * 120, .systemFont(ofSize: 48)) }
            UIColor.systemBlue.setStroke()
            let circle = UIBezierPath(ovalIn: CGRect(x: w - 520, y: 820, width: 400, height: 400))
            circle.lineWidth = 8
            circle.stroke()
            UIColor.systemOrange.withAlphaComponent(0.6).setFill()
            let pie = UIBezierPath()
            pie.move(to: CGPoint(x: w - 320, y: 1020))
            pie.addArc(withCenter: CGPoint(x: w - 320, y: 1020), radius: 200, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
            pie.close()
            pie.fill()
            UIColor.lightGray.setStroke()
            for i in 0..<5 {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 90, y: 1340 + CGFloat(i) * 70))
                p.addLine(to: CGPoint(x: w - 90, y: 1340 + CGFloat(i) * 70))
                p.lineWidth = 3
                p.stroke()
            }
        }
    }

    static func pages() -> [UIImage] { [worksheet(page: 1), worksheet(page: 2)] }

    /// Kamerabild: Arbeitsblatt quer auf dem Tisch (1920×1080).
    static func cameraFrame() -> CGImage? {
        let size = CGSize(width: 1920, height: 1080)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let sheet = worksheet()
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor(red: 0.55, green: 0.42, blue: 0.3, alpha: 1).setFill() // Tisch
            ctx.fill(CGRect(origin: .zero, size: size))
            let h: CGFloat = 1000, sw = h * sheet.size.width / sheet.size.height
            sheet.draw(in: CGRect(x: (size.width - sw) / 2, y: 40, width: sw, height: h))
        }.cgImage
    }

    /// Erfundener Wochenplan als PDF (für die Export-Vorschau).
    static func demoPDF() -> URL? {
        let page = ScanFormat.a4
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: page.height, height: page.width)).pdfData { ctx in
            ctx.beginPage()
            let font = UIFont.boldSystemFont(ofSize: 22)
            ("Wochenplan KW 46 – Klasse 5x (Beispiel)" as NSString).draw(at: CGPoint(x: 40, y: 30), withAttributes: [.font: font])
            let days = ["Mo", "Di", "Mi", "Do", "Fr"]
            let subj = ["Mathematik", "Deutsch", "NMG", "Englisch", "Sport", "Musik", "Gestalten"]
            let cw = (page.height - 80) / 5
            for (d, day) in days.enumerated() {
                let x = 40 + CGFloat(d) * cw
                (day as NSString).draw(at: CGPoint(x: x + 8, y: 80), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
                for l in 0..<5 {
                    let r = CGRect(x: x + 4, y: 110 + CGFloat(l) * 82, width: cw - 8, height: 74)
                    UIColor(hue: CGFloat((d + l) % 7) / 7, saturation: 0.25, brightness: 1, alpha: 1).setFill()
                    UIBezierPath(roundedRect: r, cornerRadius: 8).fill()
                    (subj[(d * 2 + l) % subj.count] as NSString).draw(at: CGPoint(x: r.minX + 8, y: r.minY + 10), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                }
            }
        }
        return OutFile(data: data, name: "Wochenplan KW 46.pdf", type: "application/pdf").writeTemp()
    }

    static func demoICS() -> URL? {
        let ics = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        PRODID:-//Klassentakt//Test//DE\r
        BEGIN:VEVENT\r
        UID:test-1@klassentakt.ch\r
        DTSTART:20261109T081000\r
        DTEND:20261109T085500\r
        SUMMARY:Mathematik 5x (Beispiel)\r
        END:VEVENT\r
        END:VCALENDAR\r

        """
        return OutFile(data: Data(ics.utf8), name: "Stundenplan Beispiel.ics", type: "text/calendar").writeTemp()
    }
}

/// Beamer-Vorschau im UI-Test: eigenes Fenster über allem, zeigt die Beamer-Szene verkleinert (16:9).
final class BeamerPreviewWindow: UIWindow {
    static var current: BeamerPreviewWindow?

    static func install(in scene: UIWindowScene) {
        guard current == nil else { return }
        let w = BeamerPreviewWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.isUserInteractionEnabled = false
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root
        let full = CGSize(width: 1280, height: 720), scale: CGFloat = 0.36
        w.frame = CGRect(x: 24, y: 40, width: full.width * scale, height: full.height * scale + 26)
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: w.frame.width, height: 24))
        label.text = "  Beamer (Vorschau im Test)"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .systemIndigo
        root.view.addSubview(label)
        let host = UIView(frame: CGRect(origin: .zero, size: full))
        host.layer.borderColor = UIColor.systemIndigo.cgColor
        host.layer.borderWidth = 6
        host.clipsToBounds = true
        let beamer = Beamer.shared.externalController
        root.addChild(beamer)
        beamer.view.frame = host.bounds
        beamer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(beamer.view)
        beamer.didMove(toParent: root)
        host.transform = CGAffineTransform(scaleX: scale, y: scale)
        host.center = CGPoint(x: w.frame.width / 2, y: 26 + full.height * scale / 2)
        root.view.addSubview(host)
        w.isHidden = false
        current = w
        Beamer.shared.externalConnected(true)
    }
}

extension MainViewController {
    /// UI-Test: Beamer-Vorschau einblenden und den Befehl aus `-ktRun` ausführen (einmal pro Start).
    func startTestMode() {
        guard TestMode.on, !TestModeState.started, let scene = view.window?.windowScene else { return }
        TestModeState.started = true
        if TestMode.beamerPreview { BeamerPreviewWindow.install(in: scene); TestButtons.install(in: scene, host: self) }
        guard let r = TestMode.run else { return }
        whenPageLoaded(tries: 25) { [weak self] in
            guard let self = self else { return }
            switch r {
            case "demo-export": if let u = TestMode.demoPDF() { self.offer(u) }
            case "demo-ics": if let u = TestMode.demoICS() { self.offer(u) }
            // Wie das Werkzeug «Dokumentenkamera» im Werkzeugkoffer: Nachricht über die echte Brücke.
            case "web-open-camera": self.testSendOpenCamera(tries: 10)
            case "web-open-camera-live": self.testSendOpenCamera(tries: 10, payload: "{mode: 'live'}")
            case "web-open-camera-foto": self.testSendOpenCamera(tries: 10, payload: "{mode: 'foto', allowScan: true, scanFormat: 'pdf', ref: 'test-lektion'}")
            case "demo-editing": self.testEditing()
            default: if let c = ShellCommand(rawValue: r) { self.run(c) }
            }
        }
    }
}

extension MainViewController {
    /// Befehl erst ausführen, wenn klassentakt.ch geladen ist (sonst geht z.B. der Screen noch nicht auf).
    func whenPageLoaded(tries: Int, _ then: @escaping () -> Void) {
        webView.evaluateJavaScript("document.readyState === 'complete' && !!window.klassentaktShell") { [weak self] r, _ in
            if (r as? Bool) == true || tries <= 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { then() }; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.whenPageLoaded(tries: tries - 1, then) }
        }
    }

    /// Wartet, bis die Seite geladen ist und die Brücke hat, dann `open-camera` wie aus dem Werkzeugkoffer.
    func testSendOpenCamera(tries: Int, payload p: String = "{ref: 'test-lektion'}") {
        let js = "(function(){ if (!window.klassentaktShell || document.readyState !== 'complete') return false; klassentaktShell.send('open-camera', \(p)); return true; })()"
        webView.evaluateJavaScript(js) { [weak self] r, _ in
            if (r as? Bool) != true, tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.testSendOpenCamera(tries: tries - 1, payload: p) }
            }
        }
    }

    /// Wie das Bearbeiten-Popup der Web-App: Screen öffnen, steuern, dann `editing` senden und ein
    /// erfundenes Popup in den Screen legen. Der Beamer muss das Bild davor behalten.
    func testEditing() {
        openScreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, let screen = Beamer.shared.screenWebView else { return }
            Beamer.shared.control(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.testEditPopup(open: true, in: screen, text: "Einstieg – Brüche am Kreis") }
        }
    }

    /// `editing` senden und ein erfundenes Popup in den Screen legen bzw. wieder entfernen.
    func testEditPopup(open: Bool, in screen: WKWebView, text: String) {
        if open {
            webView.evaluateJavaScript("klassentaktShell.send('editing', {open: true})", completionHandler: nil)
            let pop = "(function(){ var d = document.createElement('div'); d.id = 'ktTestPop'; d.textContent = 'Schritt bearbeiten (Test): \(text)'; d.style.cssText = 'position:fixed;left:25%;top:30%;width:50%;padding:48px;background:#fff;border-radius:24px;box-shadow:0 20px 60px rgba(0,0,0,.35);font:600 40px system-ui;z-index:99999;color:#123'; document.body.appendChild(d); })()"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { screen.evaluateJavaScript(pop, completionHandler: nil) }
        } else {
            screen.evaluateJavaScript("var d = document.getElementById('ktTestPop'); if (d) d.remove();", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.webView.evaluateJavaScript("klassentaktShell.send('editing', {open: false})", completionHandler: nil)
            }
        }
    }
}

/// Unsichtbare Knöpfe für den UI-Test (eigenes Fenster, damit sie auch über dem Screen erreichbar sind):
/// Beamer-Vorschau aus/ein (für saubere iPad-Bilder) und Bearbeiten-Popup auf/zu.
enum TestButtons {
    static var window: UIWindow?
    static var editOpen = false

    static func install(in scene: UIWindowScene, host: MainViewController) {
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 2
        w.frame = CGRect(x: 0, y: scene.coordinateSpace.bounds.height - 30, width: 150, height: 30)
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root
        func add(_ id: String, x: CGFloat, _ act: @escaping () -> Void) {
            let b = UIButton(frame: CGRect(x: x, y: 0, width: 30, height: 30))
            b.backgroundColor = .black
            b.alpha = 0.02
            b.accessibilityIdentifier = id
            b.accessibilityLabel = id
            b.addAction(UIAction { _ in act() }, for: .touchUpInside)
            root.view.addSubview(b)
        }
        add("ktPreviewHide", x: 0) { BeamerPreviewWindow.current?.isHidden = true }
        add("ktPreviewShow", x: 30) { BeamerPreviewWindow.current?.isHidden = false }
        add("ktTimer", x: 90) { [weak host] in host?.run(.timerToggle) }   // wie ⌘⇧T
        add("ktPhase", x: 120) { [weak host] in host?.run(.phaseNext) }    // wie ⌥⌘→
        add("ktEditToggle", x: 60) { [weak host] in
            guard let host = host, let screen = Beamer.shared.screenWebView else { return }
            editOpen.toggle()
            host.testEditPopup(open: editOpen, in: screen, text: "Stromkreis bauen, Schaltplan zeichnen")
        }
        w.isHidden = false
        window = w
    }
}

enum TestModeState { static var started = false }

/// UI-Test `-ktDemoKlasse`: liefert die Web-App von klassentakt.ch unter `ktdemo://klassentakt-demo/` aus.
/// Ausserhalb von klassentakt.ch startet sie als lokaler Prototyp mit ihrer Demo-Woche (ohne Anmeldung, nichts geht
/// an den Server). Die Demo enthält echte Namen; sie werden vor dem Ausliefern durch erfundene ersetzt.
final class DemoScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "ktdemo", host = "klassentakt-demo"
    static let start = URL(string: "ktdemo://klassentakt-demo/")!
    private static var html: Data?
    private var stopped = Set<ObjectIdentifier>()

    static let names: [(String, String)] = [
        ("6a · Andelfingen Zielacker", "5b · Schulhaus Beispielwil"), ("Schulhaus Zielacker, Andelfingen", "Schulhaus Sonnenberg, Beispielwil"),
        ("Herr Winberger", "Frau Muster"), ("Frau Wacker", "Frau Beispiel"), ("Herr Rüegsegger", "Herr Probst"),
        ("name:\"Florian\"", "name:\"Lena\""), ("name:\"Selina\"", "name:\"Mira\""), ("name:\"Patrick\"", "name:\"Jonas\""),
        ("kurz:\"FW\"", "kurz:\"LM\""), ("kurz:\"SW\"", "kurz:\"MB\""), ("kurz:\"PR\"", "kurz:\"JP\""),
        ("wer:\"Florian\"", "wer:\"Lena\""), ("Andelfingen", "Beispielwil"), ("Zielacker", "Sonnenberg"),
    ]

    /// Nur innerhalb von `function seed(){ … }` ersetzen, der übrige Code bleibt unberührt.
    static func sanitize(_ page: String) -> String {
        guard let a = page.range(of: "function seed(){") else { return page }
        let rest = page[a.lowerBound...]
        guard let b = rest.range(of: "P._save && P._save();") else { return page }
        var seed = String(page[a.lowerBound..<b.upperBound])
        for (from, to) in names { seed = seed.replacingOccurrences(of: from, with: to) }
        // Heute in jeder Lektion ein Ablauf mit Schritten (der Screen zeigt die aktuelle Lektion).
        seed = seed.replacingOccurrences(of: "put(K, \"evt:p2\"", with:
            "[\"nmg3\",\"mi2\",\"nmg9\",\"eng\",\"mi1\",\"nmg7\",\"nmg5\"].forEach((l, i) => E(iso(new Date()), i + 1, l));\n  put(K, \"evt:p2\"")
        return String(page[..<a.lowerBound]) + seed + String(page[b.upperBound...])
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        guard url.path.isEmpty || url.path == "/" else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            task.didFinish()
            return
        }
        let id = ObjectIdentifier(task)
        let reply: (Data) -> Void = { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, !self.stopped.contains(id) else { return }
                task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                headerFields: ["Content-Type": "text/html; charset=utf-8"])!)
                task.didReceive(data)
                task.didFinish()
            }
        }
        if let h = Self.html { reply(h); return }
        URLSession.shared.dataTask(with: URL(string: "https://klassentakt.ch/")!) { d, _, _ in
            let page = Self.sanitize(String(decoding: d ?? Data(), as: UTF8.self))
            let data = Data(page.utf8)
            Self.html = data
            reply(data)
        }.resume()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { stopped.insert(ObjectIdentifier(task)) }
}
