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
    private(set) var isBlack = false
    private var blackCover: BlackCoverViewController?

    private(set) var cameraView: UIView?

    var stateForWeb: [String: Any] {
        ["open": screenWebView != nil, "extern": isExternalConnected, "black": isBlack, "camera": cameraView != nil]
    }

    /// Dokumentenkamera auf den Beamer (über den Screen, unter «schwarz»). nil = wieder weg.
    func showCamera(_ v: UIView?) {
        cameraView = v
        externalController.setCamera(v)
        host?.beamerChanged()
    }

    /// «Bildschirm schwarz»: auf dem Beamer; ohne Beamer (oder bei Bildschirm-Synchronisierung) auf dem iPad.
    func toggleBlack() { setBlack(!isBlack) }

    func setBlack(_ on: Bool) {
        isBlack = on
        externalController.setBlack(on && isExternalConnected)
        if on && !isExternalConnected, blackCover == nil, let host = host {
            let c = BlackCoverViewController { [weak self] in self?.setBlack(false) }
            blackCover = c
            var top: UIViewController = host
            while let p = top.presentedViewController { top = p }
            top.present(c, animated: true)
        } else if !on || isExternalConnected, let c = blackCover {
            blackCover = nil
            c.dismiss(animated: true)
        }
        if isExternalConnected { host?.toast(on ? "Beamer schwarz – ⌘⇧D zeigt wieder" : "Beamer zeigt wieder") }
    }

    func toggleTimer() { host?.toast("Zuerst den Classroom Screen öffnen (⌘⇧B)") }

    /// Neues Screen-Fenster der Web-App übernehmen.
    func show(_ webView: WKWebView) {
        close()
        screenWebView = webView
        place()
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
        isExternalConnected = connected
        if isBlack { setBlack(true) }
        place()
        host?.beamerChanged()
    }

    /// Screen dorthin setzen, wo er hingehört (Beamer oder iPad-Vollbild).
    private func place() {
        guard let wv = screenWebView else { externalController.setScreen(nil); return }
        if isExternalConnected {
            if let m = modal { modal = nil; m.dismiss(animated: true) }
            externalController.setScreen(wv)
            host?.toast("Classroom Screen läuft auf dem Beamer")
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

/// Inhalt des externen Bildschirms.
final class BeamerViewController: UIViewController {
    private let placeholder = UILabel()
    private let black = UIView()
    private weak var camera: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.063, green: 0.133, blue: 0.114, alpha: 1) // #10221d wie der Screen
        placeholder.text = "Klassentakt\n\nÖffne den Classroom Screen auf dem iPad."
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
        black.backgroundColor = .black
        black.isHidden = true
        black.frame = view.bounds
        black.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(black)
    }

    func setCamera(_ v: UIView?) {
        loadViewIfNeeded()
        if camera !== v { camera?.removeFromSuperview() }
        camera = v
        guard let v = v else { return }
        v.frame = view.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(v)
        view.bringSubviewToFront(black)
    }

    func setBlack(_ on: Bool) {
        loadViewIfNeeded()
        view.bringSubviewToFront(black)
        UIView.animate(withDuration: 0.25) { self.black.alpha = on ? 1 : 0 } completion: { _ in self.black.isHidden = !on }
        if on { black.isHidden = false }
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
        view.bringSubviewToFront(black)
    }
}

/// Schwarzer Vorhang auf dem iPad selbst (kein Beamer erweitert). Tippen beendet ihn.
final class BlackCoverViewController: UIViewController {
    private let onEnd: () -> Void
    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd; super.init(nibName: nil, bundle: nil); modalPresentationStyle = .overFullScreen; modalTransitionStyle = .crossDissolve }
    required init?(coder: NSCoder) { fatalError() }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityLabel = "Bildschirm schwarz. Tippen zum Beenden."
        view.isAccessibilityElement = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(end)))
    }
    @objc private func end() { onEnd() }
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
