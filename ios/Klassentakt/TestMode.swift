import UIKit

/// UI-Test-Modus für Screenshots und Videos (Workflow «Klassentakt-shots-paketA").
/// Nur in Debug-Builds und nur mit dem Launch-Argument `-ktUITest`. Im Release ist `on` immer false.
/// - Kamera und Scanner nehmen ein erfundenes Test-Arbeitsblatt statt der Kamera.
/// - `-ktBeamerPreview`: zeigt den Beamer verkleinert oben links (der Simulator hat keinen externen Bildschirm).
/// - `-ktRun <befehl>`: führt nach dem Start einen Befehl aus (ShellCommand, Demo oder `web-open-camera`).
enum TestMode {
    static var on: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ktUITest")
        #else
        return false
        #endif
    }
    static var beamerPreview: Bool { on && ProcessInfo.processInfo.arguments.contains("-ktBeamerPreview") }
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
        if TestMode.beamerPreview { BeamerPreviewWindow.install(in: scene) }
        guard let r = TestMode.run else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            switch r {
            case "demo-export": if let u = TestMode.demoPDF() { self.offer(u) }
            case "demo-ics": if let u = TestMode.demoICS() { self.offer(u) }
            // Wie das Werkzeug «Dokumentenkamera» im Werkzeugkoffer: Nachricht über die echte Brücke.
            case "web-open-camera": self.testSendOpenCamera(tries: 20)
            default: if let c = ShellCommand(rawValue: r) { self.run(c) }
            }
        }
    }
}

extension MainViewController {
    /// Wartet, bis die Seite geladen ist und die Brücke hat, dann `open-camera` wie aus dem Werkzeugkoffer.
    func testSendOpenCamera(tries: Int) {
        let js = "(function(){ if (!window.klassentaktShell || document.readyState !== 'complete') return false; klassentaktShell.send('open-camera', {ref: 'test-lektion'}); return true; })()"
        webView.evaluateJavaScript(js) { [weak self] r, _ in
            if (r as? Bool) != true, tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.testSendOpenCamera(tries: tries - 1) }
            }
        }
    }
}

enum TestModeState { static var started = false }
