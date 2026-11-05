import UIKit
import WebKit

/// Classroom Screen auf dem Beamer:
/// - Beamer angeschlossen (HDMI/USB-C-Adapter oder AirPlay), Modus während der Nutzung umschaltbar:
///   - erweitern: Screen läuft am Beamer, das iPad zeigt den Planer mit Bild im Bild.
///     «Steuern»: derselbe Screen kommt gross aufs iPad (in Beamer-Grösse, verkleinert), der Beamer zeigt sein Live-Bild.
///   - spiegeln: Beamer zeigt das iPad-Bild.
///   Es gibt immer nur einen Screen (ein WKWebView, ein Zustand) – kopiert wird nur das Bild.
/// - Kein Beamer: Screen öffnet sich auf dem iPad im Vollbild.
/// - Solange der Screen offen ist, geht das iPad nicht in den Ruhezustand.
final class Beamer {
    static let shared = Beamer()

    let externalController = BeamerViewController()
    private(set) var screenWebView: WKWebView?
    private(set) var isExternalConnected = false
    weak var host: MainViewController?
    private var modal: ScreenViewController?

    private(set) var mode: BeamerMode = .extend
    /// Screen gross auf dem iPad (erweitern: «Steuern»; spiegeln: Screen statt Planer).
    private(set) var screenOnIPad = false
    private var mirror: LiveMirror?
    /// Bearbeiten-Popup offen (`editing`): Beamer zeigt das letzte Bild weiter.
    private(set) var isEditing = false
    private var editingRelease: DispatchWorkItem?

    /// Bild der Dokumentenkamera auf dem Beamer (über dem Screen). nil = Kamera zu.
    private(set) var cameraView: UIView?
    /// Beamer kam, bevor das Hauptfenster bereit war → Hinweis beim nächsten viewDidAppear.
    var pendingHint = false

    var stateForWeb: [String: Any] {
        ["open": screenWebView != nil, "extern": isExternalConnected, "camera": cameraView != nil,
         "mode": mode.rawValue, "steuern": isExternalConnected && screenOnIPad && screenWebView != nil]
    }

    /// Dokumentenkamera auf den Beamer. nil = wieder der Screen.
    func showCamera(_ v: UIView?) {
        let changed = (cameraView == nil) != (v == nil)
        cameraView = v
        externalController.setCamera(v)
        host?.beamerChanged()
        if changed { host?.shell.emit("camera", ["open": v != nil]) }
    }

    /// Neues Screen-Fenster der Web-App übernehmen.
    func show(_ webView: WKWebView) {
        close()
        screenWebView = webView
        screenOnIPad = mode == .mirror
        place()
        if isExternalConnected && mode == .extend { host?.toast("Classroom Screen läuft auf dem Beamer") }
        UIApplication.shared.isIdleTimerDisabled = true
        host?.beamerChanged()
    }

    func close() {
        guard let wv = screenWebView else { return }
        wv.removeFromSuperview()
        screenWebView = nil
        screenOnIPad = false
        setEditing(false)
        externalController.setScreen(nil)
        dismissModal()
        place()
        UIApplication.shared.isIdleTimerDisabled = false
        host?.beamerChanged()
    }

    /// Bearbeiten-Popup der Web-App auf/zu. Spätestens nach 15 Minuten taut der Beamer von selbst auf.
    func setEditing(_ open: Bool) {
        guard open != isEditing else { return }
        isEditing = open
        editingRelease?.cancel()
        if open {
            let w = DispatchWorkItem { [weak self] in self?.setEditing(false) }
            editingRelease = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 15 * 60, execute: w)
        }
        externalController.freeze(open)
        mirror?.paused = open
    }

    /// Erweitern ↔ Spiegeln. Beim Spiegeln kommt ein offener Screen aufs iPad (dann sieht man ihn auch vorne).
    func setMode(_ m: BeamerMode) {
        guard m != mode else { return }
        mode = m
        screenOnIPad = m == .mirror && screenWebView != nil
        place()
        host?.beamerChanged()
        host?.toast(m == .extend ? "Beamer: Erweitern" : "Beamer: Spiegeln – zeigt das iPad")
    }

    /// Screen gross aufs iPad (true) oder zurück zum Planer (false). Der Beamer läuft weiter.
    func control(_ on: Bool) {
        guard screenWebView != nil || !on else { return }
        screenOnIPad = on
        place()
        host?.beamerChanged()
    }

    func externalConnected(_ connected: Bool) {
        let wasConnected = isExternalConnected
        isExternalConnected = connected
        if connected != wasConnected { screenOnIPad = !connected || mode == .mirror }
        place()
        host?.beamerChanged()
        if connected && !wasConnected {
            if let h = host, h.view.window != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { h.beamerConnectedHint() }
            } else {
                pendingHint = true
            }
        }
    }

    /// Screen und Live-Bilder dorthin setzen, wo sie hingehören.
    private func place() {
        mirror?.stop()
        mirror = nil
        defer {
            mirror?.paused = isEditing
            externalController.showMirror(mirror != nil)
            modal?.refresh()
            host?.refreshPiP()
        }
        let wv = screenWebView
        guard isExternalConnected else {
            externalController.setScreen(nil)
            if let wv = wv { presentModal(wv, fixed: nil) } else { dismissModal() }
            return
        }
        switch mode {
        case .extend:
            if let wv = wv, screenOnIPad {
                // Gleiche Grösse wie am Beamer → nichts bricht um, der Beamer zeigt 1:1 dasselbe.
                presentModal(wv, fixed: externalController.view.bounds.size)
                mirror = LiveMirror(source: wv, target: externalController.mirrorHost, fps: 20)
            } else {
                dismissModal()
                externalController.setScreen(wv)
            }
        case .mirror:
            if let wv = wv, screenOnIPad {
                presentModal(wv, fixed: nil)
            } else {
                dismissModal()
                externalController.setScreen(wv) // läuft unsichtbar unter dem Spiegelbild weiter
            }
            if let w = host?.view.window { mirror = LiveMirror(source: w, target: externalController.mirrorHost, fps: 15) }
        }
    }

    private func presentModal(_ wv: WKWebView, fixed: CGSize?) {
        if let m = modal { m.adopt(fixed: fixed); return }
        guard let host = host else { return }
        let m = ScreenViewController(webView: wv, fixed: fixed)
        m.modalPresentationStyle = .fullScreen
        modal = m
        (host.presentedViewController == nil ? host : host.topController()).present(m, animated: true)
    }

    private func dismissModal() {
        guard let m = modal else { return }
        modal = nil
        m.dismiss(animated: true)
    }
}

/// Inhalt des externen Bildschirms: Classroom Screen der Web-App, darüber bei Bedarf die Dokumentenkamera.
/// Ohne Screen eine ruhige Platzhalterseite – der Planer wird nie gespiegelt.
final class BeamerViewController: UIViewController {
    private let placeholder = UILabel()
    private weak var camera: UIView?
    /// Live-Bild (Steuern auf dem iPad oder Spiegeln). Über dem Screen, unter der Kamera.
    let mirrorHost = UIView()
    /// Eingefrorenes Bild über allem, solange `editing` offen ist.
    private var frozen: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.063, green: 0.133, blue: 0.114, alpha: 1) // #10221d wie der Screen
        placeholder.text = "Klassentakt\n\nClassroom Screen auf dem iPad öffnen."
        placeholder.numberOfLines = 0
        placeholder.textAlignment = .center
        placeholder.textColor = UIColor(white: 1, alpha: 0.75)
        placeholder.font = .systemFont(ofSize: 34, weight: .semibold)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])
        mirrorHost.backgroundColor = .black
        mirrorHost.isHidden = true
        mirrorHost.frame = view.bounds
        mirrorHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mirrorHost)
    }

    func showMirror(_ on: Bool) {
        loadViewIfNeeded()
        mirrorHost.isHidden = !on
        if !on { mirrorHost.subviews.forEach { $0.removeFromSuperview() } }
        restack()
    }

    /// Von unten: Platzhalter, Screen, Live-Bild, Kamera, eingefrorenes Bild.
    private func restack() {
        view.bringSubviewToFront(mirrorHost)
        if let c = camera { view.bringSubviewToFront(c) }
        if let f = frozen { view.bringSubviewToFront(f) }
    }

    /// Aktuelles Beamer-Bild festhalten (true) oder wieder live zeigen (false).
    func freeze(_ on: Bool) {
        loadViewIfNeeded()
        frozen?.removeFromSuperview()
        frozen = nil
        guard on, let snap = view.snapshotView(afterScreenUpdates: false) else { return }
        snap.frame = view.bounds
        snap.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snap.accessibilityIdentifier = "beamerFrozen"
        view.addSubview(snap)
        frozen = snap
    }

    func setCamera(_ v: UIView?) {
        loadViewIfNeeded()
        if camera !== v { camera?.removeFromSuperview() }
        camera = v
        guard let v = v else { return }
        v.frame = view.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(v)
    }

    func setScreen(_ webView: WKWebView?) {
        loadViewIfNeeded()
        view.subviews.filter { $0 is WKWebView }.forEach { if $0 !== webView { $0.removeFromSuperview() } }
        placeholder.isHidden = webView != nil
        guard let wv = webView else { return }
        wv.removeFromSuperview()
        wv.transform = .identity
        wv.frame = view.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(wv)
        restack()
    }
}

/// Hinweis beim Verbinden: blockiert nichts und verschwindet von selbst.
final class BeamerHint: UIView {
    let label = UILabel()
    let button = UIButton(type: .system)
    private var hideWork: DispatchWorkItem?

    init(text: String, action: String?, onAction: @escaping () -> Void) {
        super.init(frame: .zero)
        accessibilityIdentifier = "beamerHint"
        backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        layer.cornerRadius = 22
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        var c = UIButton.Configuration.filled()
        c.title = action
        c.cornerStyle = .capsule
        c.baseBackgroundColor = .white
        c.baseForegroundColor = .black
        button.configuration = c
        button.accessibilityIdentifier = "beamerHintOpen"
        button.isHidden = action == nil
        button.addAction(UIAction { [weak self] _ in onAction(); self?.hide() }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [label, button])
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: action == nil ? -20 : -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(in v: UIView, seconds: TimeInterval) {
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        v.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: v.centerXAnchor),
            bottomAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -84),
        ])
        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func hide() {
        hideWork?.cancel()
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
    }
}

extension MainViewController {
    /// Beamer verbunden: kurzer Hinweis statt Auswahl. Ohne offenen Screen mit Knopf «Classroom Screen öffnen».
    func beamerConnectedHint() {
        guard view.window != nil else { return }
        view.subviews.compactMap { $0 as? BeamerHint }.forEach { $0.removeFromSuperview() }
        let open = Beamer.shared.screenWebView != nil
        let h = BeamerHint(text: open ? "Beamer verbunden – zeigt den Classroom Screen" : "Beamer verbunden",
                           action: open ? nil : "Classroom Screen öffnen") { [weak self] in self?.openScreen() }
        h.show(in: view, seconds: TestMode.on ? 30 : open ? 3 : 8)
    }
}

/// Screen auf dem iPad: ohne Beamer im Vollbild; mit Beamer zum Steuern (erweitern, in Beamer-Grösse verkleinert)
/// oder beim Spiegeln. Geschlossen wird über das ✕ des Screens; «Zum Planer» lässt ihn am Beamer weiterlaufen.
final class ScreenViewController: UIViewController {
    private let webView: WKWebView
    private var fixed: CGSize?
    private let bar = ScreenBar()

    init(webView: WKWebView, fixed: CGSize?) {
        self.webView = webView
        self.fixed = fixed
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.063, green: 0.133, blue: 0.114, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        adopt(fixed: fixed)
    }

    /// WebView (wieder) übernehmen, mit fester Grösse (Beamer) oder bildschirmfüllend.
    func adopt(fixed: CGSize?) {
        self.fixed = fixed
        guard isViewLoaded else { return }
        if webView.superview !== view {
            webView.removeFromSuperview()
            view.insertSubview(webView, belowSubview: bar)
        }
        view.setNeedsLayout()
        refresh()
    }

    func refresh() {
        loadViewIfNeeded()
        bar.refresh()
        view.bringSubviewToFront(bar)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard webView.superview === view else { return }
        webView.transform = .identity
        if let s = fixed, s.width > 0, s.height > 0 {
            webView.autoresizingMask = []
            webView.frame = CGRect(origin: .zero, size: s)
            let k = LiveMirror.fit(s, into: view.bounds.size)
            webView.transform = CGAffineTransform(scaleX: k, y: k)
            webView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        } else {
            webView.frame = view.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }
}
