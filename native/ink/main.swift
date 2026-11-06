// kt-ink: Handschrift → Text mit macOS Vision, auf dem Gerät, ohne Netz.
// Protokoll: pro Zeile auf stdin ein JSON-Auftrag, pro Zeile auf stdout eine JSON-Antwort.
//   Auftrag  {id, width, height, strokes: [{points: [[x, y, t, druck], …]}], png?: "data:image/png;base64,…"}
//   Antwort  {id, text, alternatives, confidence}  oder  {id, error}
// Gestartet wird es von src/ink.js, das die Aufträge vorher prüft.
import Foundation
import CoreGraphics
import ImageIO
import Vision

let SCALE: CGFloat = 3     // Striche schärfer zeichnen als das PNG der Web-App
let PAD: CGFloat = 24      // Rand in CSS-Pixeln, wie das PNG der Web-App
let LINE: CGFloat = 5      // Strichbreite in CSS-Pixeln, wie in der Web-App

/// Striche als Schwarz auf Weiss zeichnen, auf die Striche zugeschnitten.
func renderStrokes(_ strokes: [[[Double]]]) -> CGImage? {
  let pts = strokes.flatMap { $0 }.filter { $0.count >= 2 }
  guard !pts.isEmpty else { return nil }
  let xs = pts.map { CGFloat($0[0]) }, ys = pts.map { CGFloat($0[1]) }
  let minX = xs.min()! - PAD, minY = ys.min()! - PAD
  let w = Int(((xs.max()! + PAD) - minX) * SCALE), h = Int(((ys.max()! + PAD) - minY) * SCALE)
  guard w > 0, h > 0, w * h <= 40_000_000,
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
  ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  // CSS-Koordinaten (y nach unten) → Bitmap (y nach oben)
  ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: SCALE, y: -SCALE); ctx.translateBy(x: -minX, y: -minY)
  ctx.setStrokeColor(gray: 0, alpha: 1); ctx.setLineWidth(LINE); ctx.setLineCap(.round); ctx.setLineJoin(.round)
  for s in strokes {
    let p = s.filter { $0.count >= 2 }
    guard let first = p.first else { continue }
    ctx.move(to: CGPoint(x: first[0], y: first[1]))
    if p.count == 1 { ctx.addLine(to: CGPoint(x: first[0] + 0.1, y: first[1])) }
    for q in p.dropFirst() { ctx.addLine(to: CGPoint(x: q[0], y: q[1])) }
    ctx.strokePath()
  }
  return ctx.makeImage()
}

func decodePng(_ dataUrl: String) -> CGImage? {
  guard let comma = dataUrl.firstIndex(of: ","), dataUrl.hasPrefix("data:image/png;base64"),
        let data = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...])),
        let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Text erkennen. Zeilen von oben nach unten; Vorschläge = jeweils k-ter Kandidat jeder Zeile.
func recognize(_ img: CGImage) throws -> [String: Any] {
  let req = VNRecognizeTextRequest()
  req.recognitionLevel = .accurate
  req.usesLanguageCorrection = true
  if let langs = try? req.supportedRecognitionLanguages(), langs.contains("de-DE") { req.recognitionLanguages = ["de-DE"] }
  try VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
  let lines = (req.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }.map { $0.topCandidates(3) }.filter { !$0.isEmpty }
  let pick = { (k: Int) in lines.map { $0[min(k, $0.count - 1)].string }.joined(separator: " ") }
  let text = pick(0)
  var alts: [String] = []
  for k in 1..<3 { let a = pick(k); if !a.isEmpty, a != text, !alts.contains(a) { alts.append(a) } }
  let conf = lines.isEmpty ? 0 : lines.map { Double($0[0].confidence) }.reduce(0, +) / Double(lines.count)
  return ["text": text, "alternatives": alts, "confidence": (conf * 100).rounded() / 100]
}

func handle(_ line: String) -> [String: Any] {
  guard let data = line.data(using: .utf8),
        let job = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ["error": "kein JSON"] }
  let id = job["id"] ?? NSNull()
  let strokes = (job["strokes"] as? [[String: Any]] ?? []).map { ($0["points"] as? [[Double]]) ?? [] }
  guard let img = renderStrokes(strokes) ?? decodePng(job["png"] as? String ?? "") else { return ["id": id, "error": "keine Striche"] }
  do { var r = try recognize(img); r["id"] = id; return r } catch { return ["id": id, "error": "Erkennung fehlgeschlagen"] }
}

setvbuf(stdout, nil, _IOLBF, 0)
while let line = readLine(strippingNewline: true) {
  if line.isEmpty { continue }
  let out = autoreleasepool { handle(line) }
  if let d = try? JSONSerialization.data(withJSONObject: out), let s = String(data: d, encoding: .utf8) { print(s) }
}
