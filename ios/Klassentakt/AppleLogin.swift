import UIKit
import WebKit
import AuthenticationServices
import CryptoKit

/// «Mit Apple anmelden» in der iPad-App: nativer Apple-Dialog statt Web-Login.
/// Die Web-App verlinkt /auth/apple/start – die App fängt das ab, zeigt Apples Dialog
/// und schickt das Ergebnis an POST /auth/apple/native (setzt das Session-Cookie im WebView).
final class AppleLogin: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private weak var webView: WKWebView?
    private weak var anchor: UIWindow?
    private var rawNonce = ""
    private var next = "/"

    init(webView: WKWebView, anchor: UIWindow?) { self.webView = webView; self.anchor = anchor }

    static func isStart(_ url: URL?) -> Bool { MainViewController.isApp(url) && (url?.path.hasPrefix("/auth/apple/start") ?? false) }

    func start(from url: URL?) {
        if let u = url, let c = URLComponents(url: u, resolvingAgainstBaseURL: false),
           let n = c.queryItems?.first(where: { $0.name == "next" })?.value, n.hasPrefix("/"), !n.hasPrefix("//") { next = n }
        rawNonce = Self.randomNonce()
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName, .email]
        req.nonce = Self.sha256(rawNonce)
        let ctl = ASAuthorizationController(authorizationRequests: [req])
        ctl.delegate = self
        ctl.presentationContextProvider = self
        ctl.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else { return }
        let code = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "identityToken", value: token),
            URLQueryItem(name: "authorizationCode", value: code),
            URLQueryItem(name: "fullName", value: name),
            URLQueryItem(name: "nonce", value: rawNonce),
            URLQueryItem(name: "next", value: next),
        ]
        var req = URLRequest(url: URL(string: "https://klassentakt.ch/auth/apple/native")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        webView?.load(req)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // Abbruch durch den Nutzer: nichts tun, Login-Seite bleibt.
    }

    static func randomNonce(_ length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    static func sha256(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
}
