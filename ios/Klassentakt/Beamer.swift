import UIKit
import WebKit

/// Classroom Screen auf dem Beamer:
/// - Beamer angeschlossen (HDMI/USB-C-Adapter oder AirPlay «Bildschirm erweitern»): Screen läuft dort im Vollbild,
///   auf dem iPad bleibt die Planung bedienbar.
/// - Kein Beamer: Screen öffnet sich auf dem iPad im Vollbild mit «Schliessen».
/// - Solange der Screen offen ist, geht das iPad nicht in den Ruhezustand.
final class Beamer {
    static let shared = Beamer()

    let externalController = BeamerViewController()
    private(set) var screenWebView: WKWebView?
    private(set) var isExternalConnected = false
    weak var host: MainViewController?
    private var modal: ScreenViewController?

    /// Bild der Dokumentenkamera auf dem Beamer (über dem Screen). nil = Kamera zu.
    private(set) var cameraView: UIView?
    /// Beamer kam, bevor das Hauptfenster bereit war → Hinweis beim nächsten viewDidAppear.
    var pendingHint = false

    var stateForWeb: [String: Any] {
        ["open": screenWebView != nil, "extern": isExternalConnected, "camera": cameraView != nil]
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
        place()
        if isExternalConnected { host?.toast("Classroom Screen läuft auf dem Beamer") }
        UIApplication.shared.isIdleTimerDisabled = true
        host?.beamerChanged()
    }

    func close() {
        guard let wv = screenWebView else { return }
        wv.removeFromSuperview()
        screenWebView = nil
        externalController.setScreen(nil)
        if let m = modal { modal = nil; m.dismiss(animated: true) }
        UIApplication.shared.isIdleTimerDisabled = false
        host?.beamerChanged()
    }

    func externalConnected(_ connected: Bool) {
        let wasConnected = isExternalConnected
        isExternalConnected = connected
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

    /// Screen dorthin setzen, wo er hingehört (Beamer oder iPad-Vollbild).
    private func place() {
        guard let wv = screenWebView else { externalController.setScreen(nil); return }
        if isExternalConnected {
            if let m = modal { modal = nil; m.dismiss(animated: true) }
            externalController.setScreen(wv)
        } else {
            externalController.setScreen(nil)
            guard modal == nil, let host = host else { return }
            let m = ScreenViewController(webView: wv)
            m.modalPresentationStyle = .fullScreen
            modal = m
            host.present(m, animated: true)
        }
    }
}

/// Inhalt des externen Bildschirms: Classroom Screen der Web-App, darüber bei Bedarf die Dokumentenkamera.
/// Ohne Screen eine ruhige Platzhalterseite – der Planer wird nie gespiegelt.
final class BeamerViewController: UIViewController {
    private let placeholder = UILabel()
    private weak var camera: UIView?

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
        wv.frame = view.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(wv)
        if let c = camera { view.bringSubviewToFront(c) }
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

/// Screen auf dem iPad selbst (kein Beamer angeschlossen). Geschlossen wird über das ✕ des Screens.
final class ScreenViewController: UIViewController {
    private let webView: WKWebView
    init(webView: WKWebView) { self.webView = webView; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.063, green: 0.133, blue: 0.114, alpha: 1)
        webView.removeFromSuperview()
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        // Kein eigener Schliessen-Knopf: Der Screen hat sein eigenes ✕ (ruft window.close → webViewDidClose).
    }
}
