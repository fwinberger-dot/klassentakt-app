import UIKit
import WebKit
import AuthenticationServices

/// Hauptfenster: lädt klassentakt.ch. Klassentakt und Login-Anbieter bleiben in der App,
/// alle anderen Links öffnen Safari.
final class MainViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, ASWebAuthenticationPresentationContextProviding {
    static let startURL = URL(string: "https://klassentakt.ch/")!
    static let appHosts = ["klassentakt.ch"]
    // Google NICHT: Google blockiert Logins in App-Fenstern → Login über ASWebAuthenticationSession.
    static let loginHosts = ["jobnavigator.ch", "login.microsoftonline.com", "login.live.com", "login.microsoft.com"]

    private var webView: WKWebView!
    private let toastLabel = PaddingLabel()
    private var authSession: ASWebAuthenticationSession?
    private var popup: UIViewController?
    /// Streifen hinter der Statusleiste (Uhr, Akku): nimmt die Farbe der Kopfzeile der Seite an.
    private let topBar = UIView()
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
        config.userContentController.addUserScript(Self.bridgeScript())
        config.userContentController.addUserScript(Self.topColorScript())
        config.userContentController.add(WeakScriptHandler(self), name: "ktTop")

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

        webView.load(URLRequest(url: Self.startURL))
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// window.klassentaktShell – die Web-App erkennt daran die App (nur auf klassentakt.ch).
    static func bridgeScript() -> WKUserScript {
        let js = """
        (function(){
          var h = location.hostname;
          if (h !== 'klassentakt.ch' && !h.endsWith('.klassentakt.ch')) return;
          if (window.klassentaktShell) return;
          window.klassentaktShell = Object.freeze({ isShell: true, platform: 'ios', shellVersion: '\(appVersion)', features: Object.freeze(['beamer-extern']) });
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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

    func beamerChanged() {
        let js = "window.dispatchEvent(new CustomEvent('klassentakt-beamer', {detail: {open: \(Beamer.shared.screenWebView != nil), extern: \(Beamer.shared.isExternalConnected)}}))"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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

    private func topController() -> UIViewController {
        var c: UIViewController = self
        while let p = c.presentedViewController { c = p }
        return c
    }

    // MARK: Google-Login über den Browser

    /// Kann klassentakt.ch den Login schon an die App zurückgeben? (404 = Server-Teil fehlt noch)
    private func appLoginSupported(_ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "https://klassentakt.ch/auth/app/redeem?probe=1")!)
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
            let start = URL(string: "https://klassentakt.ch/auth/google/start?next=%2F&app=1")!
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
        var r = URLComponents(string: "https://klassentakt.ch/auth/app/redeem")!
        r.queryItems = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "next", value: next)]
        if let target = r.url { webView.load(URLRequest(url: target)) }
    }
}

final class PaddingLabel: UILabel {
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
