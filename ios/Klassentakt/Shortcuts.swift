import UIKit
import WebKit

/// Tastatur-Kürzel (Magic Keyboard). ⌘ gedrückt halten zeigt die Übersicht.
/// Der Name (rawValue) ist zugleich das Ereignis an die Web-App (`klassentaktShell.on('phase-next', …)`).
/// Ausnahme: Timer und Ruhe gehen als `tool` `{k}` an den Werkzeugkoffer des Classroom Screens.
enum ShellCommand: String, CaseIterable {
    case screenToggle = "screen-toggle"
    case phaseNext = "phase-next"
    case phasePrev = "phase-prev"
    case timerToggle = "tool-timer"
    case quietToggle = "tool-ruhe"
    case camera
    case scan
    case importFile = "import"
    case print
    case search
    case reload
    case shortcutsHelp = "shortcuts"

    var title: String {
        switch self {
        case .screenToggle: return "Classroom Screen an/aus"
        case .phaseNext: return "Nächste Phase"
        case .phasePrev: return "Vorherige Phase"
        case .timerToggle: return "Timer starten/stoppen"
        case .quietToggle: return "Ruhe an/aus"
        case .camera: return "Dokumentenkamera"
        case .scan: return "Dokument scannen"
        case .importFile: return "Datei importieren"
        case .print: return "Drucken"
        case .search: return "Suchen"
        case .reload: return "Neu laden"
        case .shortcutsHelp: return "Tastatur-Kürzel anzeigen"
        }
    }

    var input: String {
        switch self {
        case .screenToggle: return "b"
        case .phaseNext: return UIKeyCommand.inputRightArrow
        case .phasePrev: return UIKeyCommand.inputLeftArrow
        case .timerToggle: return "t"
        case .quietToggle: return "a"
        case .camera: return "k"
        case .scan: return "s"
        case .importFile: return "o"
        case .print: return "p"
        case .search: return "f"
        case .reload: return "r"
        case .shortcutsHelp: return "/"
        }
    }

    var modifiers: UIKeyModifierFlags {
        switch self {
        case .screenToggle, .timerToggle, .camera, .quietToggle: return [.command, .shift]
        case .phaseNext, .phasePrev, .scan: return [.command, .alternate]
        case .search, .reload, .importFile, .print, .shortcutsHelp: return .command
        }
    }

    /// Taste, die der Classroom Screen heute schon versteht (Rückfall ohne Web-Anschluss).
    var screenKey: String? {
        switch self {
        case .phaseNext: return "ArrowRight"
        case .phasePrev: return "ArrowLeft"
        case .timerToggle: return " "
        default: return nil
        }
    }

    /// Werkzeug im Classroom Screen (`TOOLS[].k` der Web-App).
    var tool: String? {
        switch self {
        case .timerToggle: return "timer"
        case .quietToggle: return "ruhe"
        default: return nil
        }
    }

    /// «⌥⌘→», «⌘⇧B» – wie in der ⌘-Übersicht von iPadOS.
    var glyph: String {
        var g = ""
        if modifiers.contains(.control) { g += "⌃" }
        if modifiers.contains(.alternate) { g += "⌥" }
        if modifiers.contains(.shift) { g += "⇧" }
        if modifiers.contains(.command) { g += "⌘" }
        switch input {
        case UIKeyCommand.inputRightArrow: g += "→"
        case UIKeyCommand.inputLeftArrow: g += "←"
        default: g += input.uppercased()
        }
        return g
    }

    var keyCommand: UIKeyCommand {
        let k = UIKeyCommand(title: title, action: #selector(MainViewController.runKeyCommand(_:)),
                             input: input, modifierFlags: modifiers, propertyList: rawValue)
        k.wantsPriorityOverSystemBehavior = true
        return k
    }
}

extension MainViewController {
    override var keyCommands: [UIKeyCommand]? { ShellCommand.allCases.map(\.keyCommand) }

    @objc func runKeyCommand(_ k: UIKeyCommand) {
        guard let id = k.propertyList as? String, let c = ShellCommand(rawValue: id) else { return }
        run(c)
    }

    func run(_ c: ShellCommand) {
        let screenOpen = Beamer.shared.screenWebView != nil
        switch c {
        case .reload:
            webView.reload()
        case .shortcutsHelp:
            let vc = UINavigationController(rootViewController: ShortcutsViewController())
            vc.modalPresentationStyle = .formSheet
            topController().present(vc, animated: true)
        case .scan:
            startScan(nil)
        case .importFile:
            pickFiles()
        case .print:
            printFromWeb([:], webView: nil)
        case .camera:
            openDocCam()
        case .screenToggle:
            if shell.emit(c.rawValue, ["open": screenOpen]) { return }
            if let wv = Beamer.shared.screenWebView {
                // Über window.close schliessen, damit die Web-App es mitbekommt; sonst hart.
                wv.evaluateJavaScript("window.close()", completionHandler: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if Beamer.shared.screenWebView === wv { Beamer.shared.close() }
                }
            } else {
                openScreen()
            }
        case .search:
            if shell.emit(c.rawValue) { return }
            let js = "(function(){ var e = document.querySelector('input[type=search], input[placeholder*=\"uch\"]'); if (!e) return false; e.focus(); if (e.select) e.select(); return true; })()"
            webView.evaluateJavaScript(js) { [weak self] r, _ in
                if (r as? Bool) != true { self?.toast("Hier gibt es keine Suche") }
            }
        case .phaseNext, .phasePrev, .timerToggle, .quietToggle:
            if let t = c.tool { if shell.emit("tool", ["k": t]) { return } } else if shell.emit(c.rawValue) { return }
            if let wv = Beamer.shared.screenWebView, let key = c.screenKey {
                wv.evaluateJavaScript(Self.keyJS(key), completionHandler: nil)
            } else if c == .quietToggle {
                toast("Ruhe gibt es im Werkzeugkoffer des Classroom Screens")
            } else {
                toast("Zuerst den Classroom Screen öffnen (⌘⇧B)")
            }
        }
    }

    /// Classroom Screen öffnen wie aus der Web-App (window.open → createWebViewWith → Beamer).
    func openScreen() {
        guard Self.isApp(webView.url) else { toast("Classroom Screen geht erst nach der Anmeldung"); return }
        let origin = TestMode.demoClass ? "'\(DemoScheme.scheme)://\(DemoScheme.host)'" : "location.origin"
        webView.evaluateJavaScript("window.open(\(origin) + '/?classroom=1', 'wp_classroom')", completionHandler: nil)
    }

    /// Tastendruck im Screen nachstellen (csKey hört auf keydown am document).
    static func keyJS(_ key: String) -> String {
        let k = key == " " ? "' '" : "'\(key)'"
        return "document.body && document.body.dispatchEvent(new KeyboardEvent('keydown', { key: \(k), bubbles: true, cancelable: true }));"
    }
}

/// Übersicht der Kürzel (zusätzlich zur ⌘-Übersicht von iPadOS, auch ohne Tastatur erreichbar).
final class ShortcutsViewController: UITableViewController {
    private let items = ShellCommand.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tastatur-Kürzel"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        tableView.allowsSelection = false
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Mit Magic Keyboard oder Smart Keyboard. ⌘ gedrückt halten zeigt die Übersicht überall."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var cfg = UIListContentConfiguration.valueCell()
        cfg.text = items[indexPath.row].title
        cfg.secondaryText = items[indexPath.row].glyph
        cfg.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        c.contentConfiguration = cfg
        return c
    }
}
