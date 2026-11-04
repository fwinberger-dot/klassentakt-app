import UIKit
import VisionKit

/// Tafelbild oder Arbeitsblatt scannen (VisionKit): Seiten werden automatisch zugeschnitten und entzerrt.
/// Ergebnis als PDF (alle Seiten) oder als Bild pro Seite an die Web-App.
enum ScanFormat: String {
    case pdf, image

    /// Längste Seite eines gescannten Bilds (reicht für Beamer und Druck, hält die Datei klein).
    static let maxSide: CGFloat = 2200
    /// A4 in Punkten (72 dpi).
    static let a4 = CGSize(width: 595.2, height: 841.8)

    /// PDF-Seite: A4 hoch oder quer, je nach Bild.
    static func pageSize(for image: CGSize) -> CGSize {
        image.width > image.height ? CGSize(width: a4.height, height: a4.width) : a4
    }

    /// Bild in die Seite einpassen (mit Rand), Seitenverhältnis bleibt.
    static func fit(_ image: CGSize, in page: CGSize, margin: CGFloat = 18) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let box = CGRect(origin: .zero, size: page).insetBy(dx: margin, dy: margin)
        let s = min(box.width / image.width, box.height / image.height)
        let w = image.width * s, h = image.height * s
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    static func scaled(_ size: CGSize, maxSide: CGFloat = maxSide) -> CGSize {
        let m = max(size.width, size.height)
        guard m > maxSide else { return size }
        let s = maxSide / m
        return CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
    }

    static func downscale(_ img: UIImage) -> UIImage {
        let target = scaled(img.size)
        guard target != img.size else { return img }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: target, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
    }

    static func jpeg(_ img: UIImage) -> Data? { downscale(img).jpegData(compressionQuality: 0.75) }

    static func pdf(_ pages: [UIImage]) -> Data {
        let meta: [String: Any] = [kCGPDFContextCreator as String: "Klassentakt", kCGPDFContextTitle as String: "Scan"]
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = meta
        let first = pageSize(for: pages.first?.size ?? a4)
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first), format: f).pdfData { ctx in
            for p in pages {
                // JPEG-Daten statt Rohbild: hält das PDF klein.
                let img = jpeg(p).flatMap(UIImage.init(data:)) ?? p
                let size = pageSize(for: img.size)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                img.draw(in: fit(img.size, in: size))
            }
        }
    }

    static func files(_ pages: [UIImage], as format: ScanFormat, date: Date = Date()) -> [OutFile] {
        switch format {
        case .pdf:
            return [OutFile(data: pdf(pages), name: OutFile.name("Scan", ext: "pdf", date: date), type: "application/pdf")]
        case .image:
            return pages.enumerated().compactMap { i, p in
                jpeg(p).map { OutFile(data: $0, name: OutFile.name("Scan", ext: "jpg", date: date, index: pages.count > 1 ? i + 1 : nil), type: "image/jpeg") }
            }
        }
    }
}

final class ScanCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    weak var host: MainViewController?
    var format: ScanFormat?
    private var keep: ScanCoordinator?

    init(host: MainViewController, format: ScanFormat?) { self.host = host; self.format = format }

    func start() {
        guard let host = host else { return }
        if TestMode.on { keep = self; let p = TestMode.pages(); if let f = format { finish(p, f) } else { askFormat(p) }; return }
        guard VNDocumentCameraViewController.isSupported else { host.toast("Scannen braucht die Kamera des iPads"); return }
        let vc = VNDocumentCameraViewController()
        vc.delegate = self
        keep = self
        host.topController().present(vc, animated: true)
    }

    func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        c.dismiss(animated: true) { [self] in
            if let f = format { finish(pages, f); return }
            askFormat(pages)
        }
    }

    func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { c.dismiss(animated: true); keep = nil }

    func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) {
        c.dismiss(animated: true)
        host?.toast("Scannen hat nicht geklappt")
        keep = nil
    }

    private func askFormat(_ pages: [UIImage]) {
        guard let host = host else { return }
        let n = pages.count
        let a = UIAlertController(title: n == 1 ? "1 Seite gescannt" : "\(n) Seiten gescannt", message: "Wie soll der Scan in Klassentakt ankommen?", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: n == 1 ? "Als PDF" : "Als ein PDF", style: .default) { _ in self.finish(pages, .pdf) })
        a.addAction(UIAlertAction(title: n == 1 ? "Als Bild" : "Als \(n) Bilder", style: .default) { _ in self.finish(pages, .image) })
        a.addAction(UIAlertAction(title: "Verwerfen", style: .destructive) { _ in self.keep = nil })
        host.topController().present(a, animated: true)
    }

    private func finish(_ pages: [UIImage], _ format: ScanFormat) {
        host?.toast("Scan wird vorbereitet …")
        DispatchQueue.global(qos: .userInitiated).async {
            let files = ScanFormat.files(pages, as: format)
            DispatchQueue.main.async {
                self.host?.deliver(files, source: "scan")
                self.keep = nil
            }
        }
    }
}

extension MainViewController {
    /// Scanner öffnen. format nil = nach dem Scannen fragen.
    func startScan(_ format: ScanFormat?) {
        ScanCoordinator(host: self, format: format).start()
    }
}
