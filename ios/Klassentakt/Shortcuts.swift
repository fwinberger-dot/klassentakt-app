import UIKit
import WebKit

/// Tastatur-Kürzel (Magic Keyboard). ⌘ gedrückt halten zeigt die Übersicht.
/// Der Name (rawValue) ist zugleich das Ereignis an die Web-App (`klassentaktShell.on('phase-next', …)`).
enum ShellCommand: String, CaseIterable {
    case screenToggle = "screen-toggle"
    case phaseNext = "phase-next"
    case phasePrev = "phase-prev"
    case timerToggle = "timer-toggle"
    case blackToggle = "black-toggle"
    case search
    case reload

    var title: String {
        switch self {
        case .screenToggle: return "Classroom Screen an/aus"
        case .phaseNext: return "Nächste Phase"
        case .phasePrev: return "Vorherige Phase"
        case .timerToggle: return "Timer starten/stoppen"
        case .blackToggle: return "Bildschirm schwarz"
        case .search: return "Suchen"
        case .reload: return "Neu laden"
        }
    }

    var input: String {
        switch self {
        case .screenToggle: return "b"
        case .phaseNext: return UIKeyCommand.inputRightArrow
        case .phasePrev: return UIKeyCommand.inputLeftArrow
        case .timerToggle: return "t"
        case .blackToggle: return "d"
        case .search: return "f"
        case .reload: return "r"
        }
    }

    var modifiers: UIKeyModifierFlags {
        switch self {
        case .screenToggle, .timerToggle, .blackToggle: return [.command, .shift]
        case .phaseNext, .phasePrev: return [.command, .alternate]
        case .search, .reload: return .command
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
        case .blackToggle:
            Beamer.shared.toggleBlack()
            shell.emit("beamer", Beamer.shared.stateForWeb)
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
        case .phaseNext, .phasePrev, .timerToggle:
            if shell.emit(c.rawValue) { return }
            if let wv = Beamer.shared.screenWebView, let key = c.screenKey {
                wv.evaluateJavaScript(Self.keyJS(key), completionHandler: nil)
            } else if c == .timerToggle {
                Beamer.shared.toggleTimer()
            } else {
                toast("Zuerst den Classroom Screen öffnen (⌘⇧B)")
            }
        }
    }

    /// Classroom Screen öffnen wie aus der Web-App (window.open → createWebViewWith → Beamer).
    func openScreen() {
        guard Self.isApp(webView.url) else { toast("Classroom Screen geht erst nach der Anmeldung"); return }
        webView.evaluateJavaScript("window.open(location.origin + '/?classroom=1', 'wp_classroom')", completionHandler: nil)
    }

    /// Tastendruck im Screen nachstellen (csKey hört auf keydown am document).
    static func keyJS(_ key: String) -> String {
        let k = key == " " ? "' '" : "'\(key)'"
        return "document.body && document.body.dispatchEvent(new KeyboardEvent('keydown', { key: \(k), bubbles: true, cancelable: true }));"
    }
}
