import UIKit
import WebKit

/// Brücke zur Web-App: `window.klassentaktShell` (Vertrag in docs/Bruecke-PaketA.md).
/// - Web → App: `klassentaktShell.send(name, payload)` und die Helfer `share`, `print`.
/// - App → Web: `klassentaktShell.on(name, fn)`. Wer `on` aufruft, meldet sich bei der App an.
///   Hört niemand zu, nimmt die App ihren eigenen Rückfall (Kürzel an den Screen, Teilen-Menü, …).
final class Shell: NSObject, WKScriptMessageHandler {
    static let handlerName = "kt"
    /// Was die App kann. Die Web-App darf ihre Knöpfe danach ein- und ausblenden.
    static let features = ["beamer-extern", "shortcuts", "scan", "camera", "beamer-layer", "share", "print", "files"]

    /// Nachrichten der Web-App (Name, Nutzlast, absendendes WebView).
    var onSend: ((String, [String: Any], WKWebView?) -> Void)?
    /// Eine Seite hört neu auf ein Ereignis (z. B. 'file' → wartende Dateien abgeben).
    var onListen: ((String) -> Void)?
    private var listeners: [String: [Weak<WKWebView>]] = [:]

    // MARK: Script

    static func script(version: String) -> WKUserScript {
        let feats = features.map { "'\($0)'" }.joined(separator: ",")
        let js = """
        (function(){
          var h = location.hostname;
          if (h !== 'klassentakt.ch' && !h.endsWith('.klassentakt.ch')) return;
          if (window.klassentaktShell) return;
          var L = {}, parts = {};
          function post(type, name, payload){ try { window.webkit.messageHandlers.kt.postMessage({ type: type, name: String(name), payload: payload == null ? {} : payload }); } catch(e){} }
          function on(name, fn){
            if (typeof fn !== 'function') return function(){};
            (L[name] = L[name] || []).push(fn); post('listen', name);
            return function(){ var a = L[name] || [], i = a.indexOf(fn); if (i >= 0) a.splice(i, 1); if (!a.length) post('unlisten', name); };
          }
          function emit(name, payload){
            (L[name] || []).slice().forEach(function(fn){ try { fn(payload); } catch(e){} });
            try { window.dispatchEvent(new CustomEvent('klassentakt-shell', { detail: { name: name, payload: payload } })); } catch(e){}
          }
          function filePart(id, i, n, b64, meta){
            var p = parts[id] = parts[id] || []; p[i] = b64;
            if (p.filter(function(x){ return x != null; }).length < n) return;
            delete parts[id];
            var bin = atob(p.join('')), u8 = new Uint8Array(bin.length);
            for (var k = 0; k < bin.length; k++) u8[k] = bin.charCodeAt(k);
            var f; try { f = new File([u8], meta.name, { type: meta.type }); } catch(e){ f = new Blob([u8], { type: meta.type }); f.name = meta.name; }
            emit('file', { source: meta.source, name: meta.name, type: meta.type, size: u8.length, file: f });
          }
          function b64(blob){ return new Promise(function(res, rej){ var r = new FileReader(); r.onload = function(){ res(String(r.result).split(',')[1] || ''); }; r.onerror = rej; r.readAsDataURL(blob); }); }
          function withData(type, o){ o = o || {};
            if (!o.blob) { post('send', type, o); return Promise.resolve(); }
            return b64(o.blob).then(function(d){ post('send', type, { name: o.name || 'Klassentakt', type: o.type || o.blob.type || 'application/octet-stream', data: d }); }); }
          window.print = function(){ post('send', 'print', {}); };
          window.klassentaktShell = Object.freeze({
            isShell: true, platform: 'ios', shellVersion: '\(version)', features: Object.freeze([\(feats)]),
            send: function(name, payload){ post('send', name, payload); },
            on: on,
            share: function(o){ return withData('share', o); },
            print: function(o){ return withData('print', o); },
            _emit: emit, _filePart: filePart
          });
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    // MARK: Empfang

    struct Message {
        enum Kind: String { case listen, unlisten, send }
        let kind: Kind
        let name: String
        let payload: [String: Any]
    }

    static func parse(_ body: Any) -> Message? {
        guard let d = body as? [String: Any], let t = d["type"] as? String, let kind = Message.Kind(rawValue: t),
              let name = d["name"] as? String, !name.isEmpty, name.count <= 64 else { return nil }
        return Message(kind: kind, name: name, payload: d["payload"] as? [String: Any] ?? [:])
    }

    static func trusted(_ host: String) -> Bool { host == "klassentakt.ch" || host.hasSuffix(".klassentakt.ch") }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        // Nur die Hauptseite von klassentakt.ch, keine eingebetteten Fremd-Inhalte (YouTube, …).
        guard m.frameInfo.isMainFrame, Self.trusted(m.frameInfo.securityOrigin.host), let msg = Self.parse(m.body) else { return }
        let wv = m.webView
        DispatchQueue.main.async {
            switch msg.kind {
            case .listen: self.listen(msg.name, wv)
            case .unlisten: self.unlisten(msg.name, wv)
            case .send: self.onSend?(msg.name, msg.payload, wv)
            }
        }
    }

    private func listen(_ name: String, _ wv: WKWebView?) {
        guard let wv = wv else { return }
        var a = (listeners[name] ?? []).filter { $0.value != nil }
        if !a.contains(where: { $0.value === wv }) { a.append(Weak(wv)) }
        listeners[name] = a
        onListen?(name)
    }

    private func unlisten(_ name: String, _ wv: WKWebView?) {
        listeners[name] = listeners[name]?.filter { $0.value != nil && $0.value !== wv }
    }

    /// Seite neu geladen: Anmeldungen dieses WebViews verfallen.
    func reset(_ wv: WKWebView) {
        for k in listeners.keys { listeners[k] = listeners[k]?.filter { $0.value != nil && $0.value !== wv } }
    }

    func isListening(_ name: String) -> Bool { !(listeners[name]?.compactMap { $0.value }.isEmpty ?? true) }

    // MARK: Senden

    /// Ereignis an alle zuhörenden Seiten. false = niemand hört zu (Rückfall nehmen).
    @discardableResult
    func emit(_ name: String, _ payload: [String: Any] = [:]) -> Bool {
        let targets = listeners[name]?.compactMap { $0.value } ?? []
        guard !targets.isEmpty, let js = Self.emitJS(name, payload) else { return false }
        targets.forEach { $0.evaluateJavaScript(js, completionHandler: nil) }
        return true
    }

    static func emitJS(_ name: String, _ payload: [String: Any]) -> String? {
        guard let p = try? JSONSerialization.data(withJSONObject: payload), let ps = String(data: p, encoding: .utf8),
              let n = try? JSONSerialization.data(withJSONObject: [name]), let ns = String(data: n, encoding: .utf8) else { return nil }
        return "window.klassentaktShell && window.klassentaktShell._emit(\(ns)[0], \(ps));"
    }

    /// Datei an die Web-App (Ereignis `file`, kommt dort als File an). false = niemand hört zu.
    @discardableResult
    func sendFile(_ data: Data, name: String, type: String, source: String) -> Bool {
        let targets = listeners["file"]?.compactMap { $0.value } ?? []
        guard !targets.isEmpty else { return false }
        let id = UUID().uuidString
        let meta: [String: Any] = ["name": name, "type": type, "source": source]
        let chunks = Self.chunks(data.base64EncodedString())
        guard let m = try? JSONSerialization.data(withJSONObject: meta), let ms = String(data: m, encoding: .utf8) else { return false }
        for wv in targets {
            for (i, c) in chunks.enumerated() {
                wv.evaluateJavaScript("window.klassentaktShell && window.klassentaktShell._filePart('\(id)', \(i), \(chunks.count), '\(c)', \(ms));", completionHandler: nil)
            }
        }
        return true
    }

    /// Base64 in Stücke (evaluateJavaScript mag keine riesigen Strings auf einmal). Base64 enthält kein ' oder \.
    static func chunks(_ s: String, size: Int = 512 * 1024) -> [String] {
        guard !s.isEmpty else { return [""] }
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: size, limitedBy: s.endIndex) ?? s.endIndex
            out.append(String(s[i..<j]))
            i = j
        }
        return out
    }
}

final class Weak<T: AnyObject> {
    weak var value: T?
    init(_ v: T) { value = v }
}
