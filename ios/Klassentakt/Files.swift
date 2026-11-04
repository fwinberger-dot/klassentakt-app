import UIKit
import WebKit
import QuickLook
import UniformTypeIdentifiers

/// Teilen-Menü, AirPrint, Import aus der Dateien-App und per Drag & Drop.
enum FileKinds {
    /// Kürzel der Web-App → Dateitypen für die Auswahl.
    static func types(_ names: [String]) -> [UTType] {
        let t = names.flatMap { n -> [UTType] in
            switch n.lowercased() {
            case "pdf": return [.pdf]
            case "image": return [.image]
            case "ics", "calendar": return [UTType(filenameExtension: "ics") ?? .calendarEvent]
            case "klassentakt": return [UTType(filenameExtension: "klassentakt") ?? .json, .json]
            case "video": return [.movie]
            case "audio": return [.audio]
            case "any", "*": return [.item]
            default: return UTType(filenameExtension: n.trimmingCharacters(in: CharacterSet(charactersIn: "."))).map { [$0] } ?? []
            }
        }
        return t.isEmpty ? [.pdf, .image] : t
    }

    static func mime(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// PDF und Bilder zeigt die App als Vorschau (mit Teilen und Drucken), alles andere geht direkt ins Teilen-Menü.
    static func previewable(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .pdf) || t.conforms(to: .image)
    }

    /// Antwort lieber herunterladen statt anzeigen? (Anhang, Kalender, unbekannter Typ)
    static func shouldDownload(mime: String?, disposition: String?, canShow: Bool) -> Bool {
        if let d = disposition?.lowercased(), d.hasPrefix("attachment") { return true }
        if let m = mime?.lowercased(), m.hasPrefix("text/calendar") || m == "application/ics" { return true }
        return !canShow
    }

    static func read(_ url: URL) -> OutFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url) else { return nil }
        return OutFile(data: d, name: url.lastPathComponent, type: mime(for: url))
    }
}

/// Vorschau (QuickLook) mit Teilen, Drucken und Markieren.
final class FilePreview: NSObject, QLPreviewControllerDataSource {
    private let urls: [URL]
    private static var current: FilePreview?
    init(_ urls: [URL]) { self.urls = urls }

    static func show(_ urls: [URL], from host: UIViewController) {
        let p = FilePreview(urls)
        current = p
        let q = QLPreviewController()
        q.dataSource = p
        host.present(q, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { urls[index] as NSURL }
}

final class DownloadHandler: NSObject, WKDownloadDelegate {
    weak var host: MainViewController?
    private var targets: [ObjectIdentifier: URL] = [:]
    init(host: MainViewController) { self.host = host }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Klassentakt/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var name = suggestedFilename.isEmpty ? "Klassentakt" : suggestedFilename
        if (name as NSString).pathExtension.isEmpty, let ext = response.mimeType.flatMap({ UTType(mimeType: $0)?.preferredFilenameExtension }) {
            name += "." + ext
        }
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        targets[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = targets.removeValue(forKey: ObjectIdentifier(download)) else { return }
        host?.offer(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        targets.removeValue(forKey: ObjectIdentifier(download))
        host?.toast("Download hat nicht geklappt")
    }
}

extension MainViewController: UIDocumentPickerDelegate, UIDropInteractionDelegate {
    // MARK: Export der Web-App → Teilen-Menü

    /// Fertige Datei aus der Web-App anbieten: Vorschau (PDF/Bild) oder Teilen-Menü (ICS, …).
    func offer(_ url: URL) {
        if FileKinds.previewable(url) { FilePreview.show([url], from: topController()) } else { share([url]) }
    }

    /// send('share', {name, type, data}) / {url} / {text}
    func shareFromWeb(_ p: [String: Any]) {
        if let b64 = p["data"] as? String, let d = Data(base64Encoded: b64) {
            let name = (p["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Klassentakt"
            var f = OutFile(data: d, name: name, type: p["type"] as? String ?? "application/octet-stream")
            if (name as NSString).pathExtension.isEmpty, let ext = UTType(mimeType: f.type)?.preferredFilenameExtension {
                f = OutFile(data: d, name: name + "." + ext, type: f.type)
            }
            if let u = f.writeTemp() { share([u]) }
        } else if let s = p["url"] as? String, let u = URL(string: s), ["https", "http", "mailto"].contains(u.scheme ?? "") {
            share([u])
        } else if let t = p["text"] as? String, !t.isEmpty {
            share([t])
        }
    }

    // MARK: AirPrint

    /// send('print', {}) = die Seite drucken, die es schickt; {name, type, data} = diese Datei.
    func printFromWeb(_ p: [String: Any], webView wv: WKWebView?) {
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = (p["name"] as? String) ?? "Klassentakt"
        info.outputType = .general
        pc.printInfo = info
        pc.printFormatter = nil
        pc.printingItem = nil
        if let b64 = p["data"] as? String, let d = Data(base64Encoded: b64) {
            if (p["type"] as? String ?? "").hasPrefix("image/") { info.outputType = .photo }
            pc.printingItem = d
        } else {
            pc.printFormatter = (wv ?? webView).viewPrintFormatter()
        }
        pc.present(animated: true)
    }

    // MARK: Import

    /// send('pickFiles', {types, multiple}) oder ⌘O. Dateien kommen als Ereignis 'file' (source 'import').
    func pickFiles(types: [String] = ["pdf", "image"], multiple: Bool = true) {
        guard shell.isListening("file") else {
            toast("Diese Klassentakt-Version übernimmt Dateien hier noch nicht – nutze «Datei hochladen»")
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: FileKinds.types(types), asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = self
        topController().present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        receive(urls.compactMap(FileKinds.read), source: "import")
    }

    /// Dateien von aussen (Dateien-App «Öffnen in», AirDrop, Drag & Drop). Beim Kaltstart ist die
    /// Web-App noch nicht bereit → warten, bis sie auf 'file' hört; sonst nach 10 s Vorschau.
    func receive(_ files: [OutFile], source: String) {
        guard !files.isEmpty else { return }
        if shell.isListening("file") { deliver(files, source: source); return }
        pendingFiles += files.map { ($0, source) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.flushPendingFiles(force: true) }
    }

    func flushPendingFiles(force: Bool = false) {
        guard !pendingFiles.isEmpty, force || shell.isListening("file") else { return }
        let all = pendingFiles
        pendingFiles = []
        Dictionary(grouping: all, by: { $0.1 }).forEach { src, items in deliver(items.map { $0.0 }, source: src) }
    }

    func openExternal(_ urls: [URL]) {
        receive(urls.filter(\.isFileURL).compactMap(FileKinds.read), source: "open")
    }

    // MARK: Drag & Drop (auf das Fenster ausserhalb der Web-Ablagen, z. B. Knopf «Beamer»)

    func installDrop(on v: UIView) {
        v.addInteraction(UIDropInteraction(delegate: self))
    }

    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: [UTType.pdf.identifier, UTType.image.identifier, UTType.item.identifier])
    }

    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        for item in session.items {
            let p = item.itemProvider
            let type = p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) ?? false } ?? UTType.data.identifier
            p.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
                guard let url = url, let d = try? Data(contentsOf: url) else { return }
                var name = p.suggestedName ?? url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
                if !ext.isEmpty && !name.hasSuffix("." + ext) { name += "." + ext }
                let mime = UTType(type)?.preferredMIMEType ?? FileKinds.mime(for: url)
                let f = OutFile(data: d, name: name, type: mime)
                DispatchQueue.main.async { self?.receive([f], source: "drop") }
            }
        }
    }
}
