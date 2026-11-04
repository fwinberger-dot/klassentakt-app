import UIKit

/// Eine Datei, die die App erzeugt hat (Scan, Foto, Import) und an die Web-App übergibt.
struct OutFile {
    let data: Data
    let name: String
    let type: String

    /// «Scan 2026-11-04 09.41.pdf», bei mehreren Seiten «… (2).jpg».
    static func name(_ prefix: String, ext: String, date: Date = Date(), index: Int? = nil) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let n = index.map { " (\($0))" } ?? ""
        return "\(prefix) \(f.string(from: date))\(n).\(ext)"
    }

    /// In den temporären Ordner schreiben (für Teilen-Menü und Vorschau).
    func writeTemp() -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Klassentakt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = dir.appendingPathComponent(safe)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

extension MainViewController {
    /// Dateien an die Web-App (Ereignis `file`). Kann die Web-App das noch nicht,
    /// bleibt nichts verloren: Vorschau mit Teilen-Menü (Dateien, AirDrop, Fotos, Drucken).
    func deliver(_ files: [OutFile], source: String) {
        guard !files.isEmpty else { return }
        let taken = files.map { shell.sendFile($0.data, name: $0.name, type: $0.type, source: source) }
        if taken.allSatisfy({ $0 }) {
            toast(files.count == 1 ? "An Klassentakt übergeben" : "\(files.count) Dateien an Klassentakt übergeben")
            return
        }
        let urls = files.compactMap { $0.writeTemp() }
        guard !urls.isEmpty else { toast("Datei konnte nicht gesichert werden"); return }
        showFallback(urls)
    }

    func topController() -> UIViewController {
        var c: UIViewController = self
        while let p = c.presentedViewController { c = p }
        return c
    }

    /// Rückfall: Vorschau (PDF/Bild, mit Teilen und Drucken) oder Teilen-Menü.
    func showFallback(_ urls: [URL]) {
        toast("Diese Klassentakt-Version übernimmt das noch nicht direkt – sichern oder teilen")
        if urls.allSatisfy(FileKinds.previewable) { FilePreview.show(urls, from: topController()) } else { share(urls) }
    }

    func share(_ items: [Any], hint: String? = nil, from source: UIView? = nil) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let top = topController()
        if let p = vc.popoverPresentationController {
            let v = source ?? top.view!
            p.sourceView = v
            p.sourceRect = source == nil ? CGRect(x: v.bounds.midX, y: v.bounds.midY, width: 1, height: 1) : v.bounds
            p.permittedArrowDirections = source == nil ? [] : .any
        }
        if let hint = hint { toast(hint) }
        top.present(vc, animated: true)
    }
}
