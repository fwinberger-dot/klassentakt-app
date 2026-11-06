import UIKit
import WebKit
import AuthenticationServices

/// Hauptfenster: lädt klassentakt.ch. Klassentakt und Login-Anbieter bleiben in der App,
/// alle anderen Links öffnen Safari.
final class MainViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, ASWebAuthenticationPresentationContextProviding {
    /// Server aus der Build-Einstellung KT_SERVER. Nur klassentakt.ch oder eine Subdomain, sonst klassentakt.ch.
    static let server: String = serverName(Bundle.main.object(forInfoDictionaryKey: "KTServer") as? String)
    static let startURL = URL(string: "https://\(server)/")!

    static func serverName(_ raw: String?) -> String {
        let h = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let ok = h == "klassentakt.ch" || (h.hasSuffix(".klassentakt.ch") && h.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil)
        return ok ? h : "klassentakt.ch"
    }
    static let appHosts = ["klassentakt.ch"]
    // Google NICHT: Google blockiert Logins in App-Fenstern → Login über ASWebAuthenticationSession.
    static let loginHosts = ["jobnavigator.ch", "login.microsoftonline.com", "login.live.com", "login.microsoft.com"]

    private(set) var webView: WKWebView!
    let shell = Shell()
    private let toastLabel = PaddingLabel()
    private var authSession: ASWebAuthenticationSession?
    private var popup: UIViewController?
    /// Streifen hinter der Statusleiste (Uhr, Akku): nimmt die Farbe der Kopfzeile der Seite an.
    private let topBar = UIView()
    var pendingFiles: [(OutFile, String)] = []
    private lazy var pip = BeamerPiP(host: self)
    lazy var downloads = DownloadHandler(host: self)
    private var topIsDark = false

    // MARK: Aufbau

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "LaunchBackground")
        Beamer.shared.host = self

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.applicationNameForUserAgent = "KlassentaktApp/\(Self.appVersion)"
        config.userContentController.addUserScript(Shell.script(version: Self.appVersion))
        config.userContentController.addUserScript(Self.topColorScript())
        if TestMode.demoClass { config.userContentController.addUserScript(TestMode.demoClassScript()) }
        config.userContentController.add(WeakScriptHandler(self), name: "ktTop")
        config.userContentController.add(shell, name: Shell.handlerName)
        shell.onSend = { [weak self] name, payload, wv in self?.handleShell(name, payload, from: wv) }
        shell.onListen = { [weak self] name in
            if name == "file" { self?.flushPendingFiles() }
            if name == "camera" { self?.shell.emit("camera", ["open": Beamer.shared.cameraView != nil]) }
        }

        topBar.backgroundColor = .white
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.underPageBackgroundColor = .white
        webView.isOpaque = false
        webView.backgroundColor = .white
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        toastLabel.alpha = 0
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        toastLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        toastLabel.layer.cornerRadius = 18
        toastLabel.clipsToBounds = true
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        installDrop(on: view)
        installTestBand()
        pip.isHidden = true
        view.addSubview(pip)
        view.bringSubviewToFront(toastLabel)
        webView.load(URLRequest(url: Self.startURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if TestMode.on { startTestMode() }
        if Beamer.shared.pendingHint {
            Beamer.shared.pendingHint = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.beamerConnectedHint() }
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Meldet die Hintergrundfarbe ganz oben auf der Seite (Kopfzeile) an die App –
    /// beim Laden, Scrollen, Drehen und Wechsel des Designs (hell/dunkel/Theme).
    static func topColorScript() -> WKUserScript {
        let js = """
        (function(){
          var last = '';
          function bg(el){ while (el && el !== document.documentElement) { var c = getComputedStyle(el).backgroundColor; if (c && c !== 'transparent' && !/rgba\\(.*,\\s*0\\)$/.test(c)) return c; el = el.parentElement; }
            var b = getComputedStyle(document.body || document.documentElement).backgroundColor; return b || 'rgb(255,255,255)'; }
          function report(){ try { var el = document.elementFromPoint(Math.max(1, innerWidth / 2), 1); var c = bg(el);
            if (c !== last) { last = c; window.webkit.messageHandlers.ktTop.postMessage(c); } } catch(e){} }
          var t = 0; function soon(){ clearTimeout(t); t = setTimeout(report, 60); }
          addEventListener('load', report); addEventListener('resize', soon); addEventListener('scroll', soon, { passive: true, capture: true });
          document.addEventListener('DOMContentLoaded', function(){
            report();
            try { new MutationObserver(soon).observe(document.documentElement, { attributes: true, subtree: true, attributeFilter: ['class', 'data-theme', 'style'] }); } catch(e){}
          });
          setInterval(report, 1500);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    /// «rgb(255, 255, 255)» / «rgba(…)» → UIColor
    static func color(fromCSS css: String) -> UIColor? {
        let nums = css.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).filter { !$0.isEmpty }.compactMap(Double.init)
        guard nums.count >= 3 else { return nil }
        let a = nums.count >= 4 ? nums[3] : 1
        if a < 0.5 { return nil }
        return UIColor(red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255, alpha: 1)
    }

    func setTopColor(_ c: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let dark = (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
        UIView.animate(withDuration: 0.15) { self.topBar.backgroundColor = c }
        webView.underPageBackgroundColor = c
        if dark != topIsDark { topIsDark = dark; setNeedsStatusBarAppearanceUpdate() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { topIsDark ? .lightContent : .darkContent }

    // MARK: Hilfen

    private static func host(_ url: URL?) -> String { url?.host?.lowercased() ?? "" }
    private static func matches(_ host: String, _ list: [String]) -> Bool { list.contains { host == $0 || host.hasSuffix("." + $0) } }
    static func isApp(_ url: URL?) -> Bool { matches(host(url), appHosts) }
    static func isLogin(_ url: URL?) -> Bool { matches(host(url), loginHosts) }
    static func isGoogleAuth(_ url: URL?) -> Bool { matches(host(url), ["accounts.google.com"]) }
    static func isGoogleStart(_ url: URL?) -> Bool { isApp(url) && (url?.path.hasPrefix("/auth/google/start") ?? false) }
    static func isScreen(_ url: URL?) -> Bool {
        guard let url = url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.queryItems?.contains { $0.name == "classroom" && $0.value == "1" } ?? false
    }

    func toast(_ text: String) {
        toastLabel.text = text
        UIView.animate(withDuration: 0.25) { self.toastLabel.alpha = 1 }
        UIView.animate(withDuration: 0.4, delay: 2.6, options: []) { self.toastLabel.alpha = 0 }
    }

    /// «TEST · staging»: sichtbar, sobald die App nicht gegen klassentakt.ch läuft (Verwechslung mit dem Betrieb vermeiden).
    static func testBandText(_ server: String) -> String? {
        server == "klassentakt.ch" ? nil : "TEST · " + (server.components(separatedBy: ".").first ?? server)
    }

    private func installTestBand() {
        guard let t = Self.testBandText(Self.server) else { return }
        let l = PaddingLabel()
        l.insets = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
        l.text = t
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = .white
        l.backgroundColor = .systemOrange
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        l.isUserInteractionEnabled = false
        l.accessibilityIdentifier = "testBand"
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
        ])
    }

    /// Bild im Bild nach jeder Änderung am Beamer (Modus, Screen auf/zu, verbunden).
    func refreshPiP() {
        guard isViewLoaded else { return }
        view.bringSubviewToFront(pip)
        view.bringSubviewToFront(toastLabel)
        pip.refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !pip.isHidden { pip.keepInside() }
    }

    func beamerChanged() {
        let js = "window.dispatchEvent(new CustomEvent('klassentakt-beamer', {detail: {open: \(Beamer.shared.screenWebView != nil), extern: \(Beamer.shared.isExternalConnected)}}))"
        webView?.evaluateJavaScript(js, completionHandler: nil)
        shell.emit("beamer", Beamer.shared.stateForWeb)
    }

    /// Nachrichten der Web-App über window.klassentaktShell.send (Vertrag: docs/Bruecke-PaketA.md).
    func handleShell(_ name: String, _ payload: [String: Any], from wv: WKWebView?) {
        switch name {
        case "command":
            if let id = payload["id"] as? String, let c = ShellCommand(rawValue: id) { run(c) }
        case "open-camera", "close-camera", "camera":
            // «camera» {open} ist der alte Name aus Fassung 1.
            let want = name == "open-camera" || (name == "camera" && payload["open"] as? Bool ?? true)
            let cam = DocCamViewController.current
            if want, cam == nil {
                let mode = payload["mode"] as? String
                openDocCam(ref: Self.ref(payload), liveOnly: mode == "live", capture: mode == "foto",
                           allowScan: payload["allowScan"] as? Bool ?? false,
                           scanFormat: (payload["scanFormat"] as? String).flatMap(ScanFormat.init(rawValue:)))
            }
            if !want { cam?.close() }
        case "editing":
            // Bearbeiten-Popup im Screen: Beamer behält das letzte Bild, das Popup bleibt privat.
            Beamer.shared.setEditing(payload["open"] as? Bool ?? false)
        case "share":
            shareFromWeb(payload)
        case "print":
            printFromWeb(payload, webView: wv)
        case "pickFiles":
            pickFiles(types: payload["types"] as? [String] ?? ["pdf", "image"], multiple: payload["multiple"] as? Bool ?? true)
        case "open-scanner", "scan":
            startScan((payload["format"] as? String).flatMap(ScanFormat.init(rawValue:)), ref: Self.ref(payload))
        default:
            break
        }
    }

    /// `ref` der Web-App (geht im Ereignis `file` unverändert zurück), höchstens 200 Zeichen.
    static func ref(_ payload: [String: Any]) -> String? {
        guard let r = payload["ref"] as? String, !r.isEmpty else { return nil }
        return String(r.prefix(200))
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // <a download> (Export als PDF, ICS, JSON …) → Download → Teilen-Menü
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        let url = navigationAction.request.url
        guard let scheme = url?.scheme?.lowercased() else { decisionHandler(.allow); return }
        if scheme == "about" || scheme == "file" || scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
        if scheme == "klassentakt", let url = url { decisionHandler(.cancel); handleDeepLink(url); return }
        if Self.isGoogleStart(url) || Self.isGoogleAuth(url) {
            decisionHandler(.cancel)
            closePopup()
            startGoogleLogin()
            return
        }
        if Self.isApp(url) || Self.isLogin(url) { decisionHandler(.allow); return }
        // Eingebettete Inhalte (iframes, z.B. YouTube, Spotify) dürfen laden; nur Seitenwechsel gehen nach Safari.
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if let url = url, ["http", "https", "mailto", "tel"].contains(scheme) { UIApplication.shared.open(url) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { shell.reset(webView) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let dl = FileKinds.shouldDownload(mime: navigationResponse.response.mimeType,
                                          disposition: http?.value(forHTTPHeaderField: "Content-Disposition"),
                                          canShow: navigationResponse.canShowMIMEType)
        decisionHandler(dl ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled || ns.code == 102 /* Frame load interrupted */ { return }
        showOffline(in: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    private func showOffline(in wv: WKWebView) {
        guard let file = Bundle.main.url(forResource: "offline", withExtension: "html") else { return }
        wv.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }

    // MARK: Neue Fenster (window.open)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let blank = url == nil || url?.absoluteString == "" || url?.absoluteString == "about:blank"
        let fromApp = Self.isApp(webView.url)

        if Self.isGoogleStart(url) || Self.isGoogleAuth(url) { startGoogleLogin(); return nil }

        // Datei in neuem Fenster (blob:/data:, z. B. PDF-Export mit target=_blank) → Vorschau/Teilen statt leerem Fenster
        if navigationAction.shouldPerformDownload || ["blob", "data"].contains(url?.scheme?.lowercased() ?? "") {
            webView.startDownload(using: navigationAction.request) { [weak self] d in d.delegate = self?.downloads }
            return nil
        }

        // Classroom Screen → Beamer oder iPad-Vollbild
        if fromApp && (Self.isScreen(url) || blank) {
            let screen = WKWebView(frame: .zero, configuration: configuration)
            screen.navigationDelegate = self
            screen.uiDelegate = self
            screen.isOpaque = false
            screen.backgroundColor = .black
            Beamer.shared.show(screen)
            return screen
        }

        // Login-Popups (Jobnavigator, Microsoft) als Blatt über der App
        if Self.isApp(url) || Self.isLogin(url) {
            let child = WKWebView(frame: .zero, configuration: configuration)
            child.navigationDelegate = self
            child.uiDelegate = self
            let vc = UIViewController()
            vc.view = child
            let nav = UINavigationController(rootViewController: vc)
            vc.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.closePopup() })
            nav.modalPresentationStyle = .formSheet
            popup = nav
            present(nav, animated: true)
            return child
        }

        if let url = url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === Beamer.shared.screenWebView { Beamer.shared.close() } else { closePopup() }
    }

    private func closePopup() {
        if let p = popup { popup = nil; p.dismiss(animated: true) }
    }

    // MARK: Test-Server mit Basic-Auth (z.B. staging)

    /// Zugang zum Test-Server: tippt man selbst ein, gilt nur, solange die App läuft. Nie im Build oder Repo.
    private static var basicCredential: URLCredential?

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let ps = challenge.protectionSpace
        guard ps.authenticationMethod == NSURLAuthenticationMethodHTTPBasic, ps.host == Self.server, Self.server != "klassentakt.ch" else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if challenge.previousFailureCount == 0, let c = Self.basicCredential { completionHandler(.useCredential, c); return }
        askBasic(host: ps.host, wrong: challenge.previousFailureCount > 0, completionHandler)
    }

    private func askBasic(host: String, wrong: Bool, _ done: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Beim ersten Laden ist das Fenster evtl. noch nicht da.
        guard view.window != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.askBasic(host: host, wrong: wrong, done) }
            return
        }
        let a = UIAlertController(title: "Test-Server", message: (wrong ? "Zugang stimmt nicht. " : "") + "\(host) ist geschützt. Zugang eingeben – gilt, bis die App beendet wird.", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Benutzer"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no; $0.textContentType = .username }
        a.addTextField { $0.placeholder = "Passwort"; $0.isSecureTextEntry = true; $0.textContentType = .password }
        a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in done(.cancelAuthenticationChallenge, nil) })
        a.addAction(UIAlertAction(title: "Anmelden", style: .default) { [weak a] _ in
            let c = URLCredential(user: a?.textFields?[0].text ?? "", password: a?.textFields?[1].text ?? "", persistence: .forSession)
            Self.basicCredential = c
            done(.useCredential, c)
        })
        topController().present(a, animated: true)
    }

    // MARK: Kamera/Mikrofon nur für Klassentakt

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let ok = origin.host == "klassentakt.ch" || origin.host.hasSuffix(".klassentakt.ch")
        decisionHandler(ok ? .grant : .deny)
    }

    // JS-Dialoge (alert/confirm) als native Hinweise
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        topController().present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        topController().present(a, animated: true)
    }

    // MARK: Google-Login über den Browser

    /// Kann klassentakt.ch den Login schon an die App zurückgeben? (404 = Server-Teil fehlt noch)
    private func appLoginSupported(_ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "https://\(Self.server)/auth/app/redeem?probe=1")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 404
            DispatchQueue.main.async { done(code != 404) }
        }.resume()
    }

    func startGoogleLogin() {
        guard authSession == nil else { return }
        appLoginSupported { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                let a = UIAlertController(title: "Google-Anmeldung kommt bald",
                                          message: "Google lässt die Anmeldung nicht in Apps zu. Wir bauen gerade den Weg über Safari. Bis dahin: mit Jobnavigator-Passwort oder E-Mail anmelden.",
                                          preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.topController().present(a, animated: true)
                return
            }
            let start = URL(string: "https://\(Self.server)/auth/google/start?next=%2F&app=1")!
            let session = ASWebAuthenticationSession(url: start, callbackURLScheme: "klassentakt") { [weak self] url, _ in
                self?.authSession = nil
                if let url = url { self?.handleDeepLink(url) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    /// klassentakt://auth?code=…&next=/… → Code auf klassentakt.ch einlösen (setzt das Login-Cookie in der App).
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "klassentakt", url.host == "auth",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let code = c.queryItems?.first { $0.name == "code" }?.value ?? ""
        guard code.range(of: "^[A-Za-z0-9_-]{16,200}$", options: .regularExpression) != nil else { return }
        var next = c.queryItems?.first { $0.name == "next" }?.value ?? "/"
        if !next.hasPrefix("/") || next.hasPrefix("//") { next = "/" }
        var r = URLComponents(string: "https://\(Self.server)/auth/app/redeem")!
        r.queryItems = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "next", value: next)]
        if let target = r.url { webView.load(URLRequest(url: target)) }
    }
}

class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 9, left: 18, bottom: 9, right: 18)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

/// Verhindert, dass der WKUserContentController den ViewController festhält.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: MainViewController?
    init(_ t: MainViewController) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard m.name == "ktTop", let css = m.body as? String, let col = MainViewController.color(fromCSS: css) else { return }
        DispatchQueue.main.async { self.target?.setTopColor(col) }
    }
}
