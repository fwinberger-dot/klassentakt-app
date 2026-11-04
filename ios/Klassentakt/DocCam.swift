import UIKit
import AVFoundation
import CoreImage

/// Dokumentenkamera: Live-Bild der iPad-Kamera, auf dem Beamer im Vollbild.
/// Zoom mit zwei Fingern, Einfrieren (Standbild, iPad darf bewegt werden), Drehen, Taschenlampe, Foto an die Web-App.
final class DocCam: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = DocCam()

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ch.klassentakt.doccam")
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var device: AVCaptureDevice?
    private var output: AVCaptureVideoDataOutput?
    private var configured = false
    private var busy = false

    /// Ausgaben (iPad-Vorschau, Beamer). Bekommen jedes Bild als layer.contents.
    private var views: [Weak<DocCamView>] = []
    private(set) var lastImage: CGImage?

    private(set) var isRunning = false
    private(set) var isFrozen = false
    /// Vierteldrehungen im Uhrzeigersinn (0–3).
    private(set) var quarterTurns = 0
    private(set) var zoom: CGFloat = 1
    private(set) var torchOn = false
    var onChange: (() -> Void)?

    var hasTorch: Bool { device?.hasTorch ?? false }
    var maxZoom: CGFloat { Self.zoomLimit(device?.maxAvailableVideoZoomFactor ?? 1) }

    // MARK: Logik (getestet)

    static func zoomLimit(_ deviceMax: CGFloat) -> CGFloat { max(1, min(deviceMax, 10)) }
    static func clampZoom(_ z: CGFloat, max m: CGFloat) -> CGFloat { min(max(z, 1), max(1, m)) }
    static func orientation(quarterTurns q: Int) -> CGImagePropertyOrientation {
        switch ((q % 4) + 4) % 4 { case 1: return .right; case 2: return .down; case 3: return .left; default: return .up }
    }
    static func zoomLabel(_ z: CGFloat) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: Double(z))) ?? "1.0") + "×"
    }
    static func videoOrientation(_ o: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    // MARK: Start/Stopp

    /// Berechtigung prüfen; done(true) = Kamera darf laufen.
    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    func attach(_ v: DocCamView) {
        views = views.filter { $0.value != nil && $0.value !== v } + [Weak(v)]
        if let img = lastImage { v.show(img) }
    }

    func detach(_ v: DocCamView) { views = views.filter { $0.value != nil && $0.value !== v } }

    func start(orientation: UIInterfaceOrientation) -> Bool {
        if !configured && !configure() { return false }
        isFrozen = false
        setOrientation(orientation)
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
        isRunning = true
        onChange?()
        return true
    }

    func stop() {
        setTorch(false)
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        isRunning = false
        isFrozen = false
        lastImage = nil
        onChange?()
    }

    private func configure() -> Bool {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev) else { return false }
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard session.canAddInput(input) else { session.commitConfiguration(); return false }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(out) else { session.commitConfiguration(); return false }
        session.addOutput(out)
        session.commitConfiguration()
        if (try? dev.lockForConfiguration()) != nil {
            if dev.isFocusModeSupported(.continuousAutoFocus) { dev.focusMode = .continuousAutoFocus }
            if dev.isAutoFocusRangeRestrictionSupported { dev.autoFocusRangeRestriction = .near }
            if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            dev.unlockForConfiguration()
        }
        device = dev
        output = out
        configured = true
        return true
    }

    func setOrientation(_ o: UIInterfaceOrientation) {
        guard let c = output?.connection(with: .video), c.isVideoOrientationSupported else { return }
        c.videoOrientation = Self.videoOrientation(o)
    }

    // MARK: Bedienung

    func toggleFreeze() { isFrozen.toggle(); onChange?() }

    func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        onChange?()
    }

    func setZoom(_ z: CGFloat) {
        guard let dev = device else { return }
        let v = Self.clampZoom(z, max: maxZoom)
        if (try? dev.lockForConfiguration()) != nil {
            dev.videoZoomFactor = v
            dev.unlockForConfiguration()
            zoom = v
            onChange?()
        }
    }

    func setTorch(_ on: Bool) {
        guard let dev = device, dev.hasTorch, (try? dev.lockForConfiguration()) != nil else { torchOn = false; return }
        if on, dev.isTorchModeSupported(.on) { try? dev.setTorchModeOn(level: 0.6) } else { dev.torchMode = .off }
        dev.unlockForConfiguration()
        torchOn = on && dev.torchMode == .on
        onChange?()
    }

    /// Aktuelles Bild (so, wie es auf dem Beamer steht) als JPEG.
    func photo() -> OutFile? {
        guard let img = lastImage, let data = UIImage(cgImage: img).jpegData(compressionQuality: 0.85) else { return nil }
        return OutFile(data: data, name: OutFile.name("Dokumentenkamera", ext: "jpg"), type: "image/jpeg")
    }

    // MARK: Bilder

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isFrozen, !busy, let px = CMSampleBufferGetImageBuffer(sb) else { return }
        let ciImage = CIImage(cvPixelBuffer: px).oriented(Self.orientation(quarterTurns: quarterTurns))
        guard let cg = ci.createCGImage(ciImage, from: ciImage.extent) else { return }
        busy = true
        DispatchQueue.main.async {
            self.lastImage = cg
            self.views.compactMap { $0.value }.forEach { $0.show(cg) }
            self.queue.async { self.busy = false }
        }
    }
}

/// Zeigt das Kamerabild eingepasst auf schwarzem Grund.
final class DocCamView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
        isAccessibilityElement = true
        accessibilityLabel = "Bild der Dokumentenkamera"
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ img: CGImage) { layer.contents = img }
}

/// Dokumentenkamera auf dem iPad: Vorschau und Knöpfe. Das Bild läuft gleichzeitig auf dem Beamer.
final class DocCamViewController: UIViewController {
    private let cam = DocCam.shared
    private let preview = DocCamView()
    private let beamerView = DocCamView()
    private let status = PaddingLabel()
    private let bar = UIStackView()
    private let freezeBtn = UIButton(type: .system)
    private let torchBtn = UIButton(type: .system)
    private let zoomBtn = UIButton(type: .system)
    private var pinchStart: CGFloat = 1
    weak var host: MainViewController?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.frame = view.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(preview)
        preview.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        dbl.numberOfTapsRequired = 2
        preview.addGestureRecognizer(dbl)
        preview.isUserInteractionEnabled = true

        status.textColor = .white
        status.backgroundColor = UIColor(white: 0, alpha: 0.55)
        status.font = .systemFont(ofSize: 15, weight: .semibold)
        status.layer.cornerRadius = 16
        status.clipsToBounds = true
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)

        bar.axis = .horizontal
        bar.spacing = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        let bg = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        bg.layer.cornerRadius = 22
        bg.clipsToBounds = true
        bg.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bg)
        bg.contentView.addSubview(bar)

        setup(freezeBtn, "Einfrieren", "pause.circle", #selector(freeze))
        let rotateBtn = UIButton(type: .system); setup(rotateBtn, "Drehen", "rotate.right", #selector(rotate))
        setup(zoomBtn, "1.0×", "plus.magnifyingglass", #selector(resetZoom))
        setup(torchBtn, "Licht", "flashlight.off.fill", #selector(torch))
        let photoBtn = UIButton(type: .system); setup(photoBtn, "Foto übernehmen", "camera.fill", #selector(photo))
        let closeBtn = UIButton(type: .system); setup(closeBtn, "Schliessen", "xmark.circle.fill", #selector(close))
        [freezeBtn, rotateBtn, zoomBtn, torchBtn, photoBtn, closeBtn].forEach(bar.addArrangedSubview)

        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bg.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            bg.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bg.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.topAnchor.constraint(equalTo: bg.contentView.topAnchor, constant: 8),
            bar.bottomAnchor.constraint(equalTo: bg.contentView.bottomAnchor, constant: -8),
            bar.leadingAnchor.constraint(equalTo: bg.contentView.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: bg.contentView.trailingAnchor, constant: -14),
        ])

        cam.onChange = { [weak self] in self?.refresh() }
        cam.attach(preview)
        cam.attach(beamerView)
        Beamer.shared.showCamera(beamerView)
        if !cam.start(orientation: view.window?.windowScene?.interfaceOrientation ?? .landscapeLeft) {
            status.text = "Kamera nicht verfügbar"
        }
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let o = view.window?.windowScene?.interfaceOrientation { cam.setOrientation(o) }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            if let o = self?.view.window?.windowScene?.interfaceOrientation { self?.cam.setOrientation(o) }
        }
    }

    private func setup(_ b: UIButton, _ title: String, _ symbol: String, _ action: Selector) {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol)
        c.title = title
        c.imagePlacement = .top
        c.imagePadding = 4
        c.baseForegroundColor = .white
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = UIFont.systemFont(ofSize: 13, weight: .medium); return a
        }
        b.configuration = c
        b.addTarget(self, action: action, for: .touchUpInside)
    }

    private func setTitle(_ b: UIButton, _ title: String, _ symbol: String) {
        b.configuration?.title = title
        b.configuration?.image = UIImage(systemName: symbol)
    }

    private func refresh() {
        setTitle(freezeBtn, cam.isFrozen ? "Live" : "Einfrieren", cam.isFrozen ? "play.circle" : "pause.circle")
        setTitle(zoomBtn, DocCam.zoomLabel(cam.zoom), cam.zoom > 1.01 ? "minus.magnifyingglass" : "plus.magnifyingglass")
        torchBtn.isHidden = !cam.hasTorch
        setTitle(torchBtn, cam.torchOn ? "Licht aus" : "Licht", cam.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
        if cam.isRunning || cam.isFrozen {
            var t = Beamer.shared.isExternalConnected ? "● Live auf dem Beamer" : "● Live"
            if cam.isFrozen { t = "❚❚ Standbild – iPad darf bewegt werden" }
            status.text = t
        }
        Beamer.shared.host?.shell.emit("beamer", Beamer.shared.stateForWeb)
    }

    // MARK: Aktionen

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { pinchStart = cam.zoom }
        if g.state == .changed { cam.setZoom(pinchStart * g.scale) }
    }

    @objc private func resetZoom() { cam.setZoom(1) }
    @objc private func freeze() { cam.toggleFreeze() }
    @objc private func rotate() { cam.rotate() }
    @objc private func torch() { cam.setTorch(!cam.torchOn) }

    @objc private func photo() {
        guard let f = cam.photo() else { host?.toast("Noch kein Bild"); return }
        UIView.animate(withDuration: 0.08, animations: { self.preview.alpha = 0.3 }) { _ in
            UIView.animate(withDuration: 0.2) { self.preview.alpha = 1 }
        }
        host?.deliver([f], source: "camera")
    }

    @objc func close() {
        cam.stop()
        cam.detach(preview)
        cam.detach(beamerView)
        cam.onChange = nil
        Beamer.shared.showCamera(nil)
        dismiss(animated: true)
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Einfrieren/Live", action: #selector(freeze), input: " "),
            UIKeyCommand(title: "Drehen", action: #selector(rotate), input: "r"),
            UIKeyCommand(title: "Licht", action: #selector(torch), input: "l"),
            UIKeyCommand(title: "Foto übernehmen", action: #selector(photo), input: "\r"),
            UIKeyCommand(title: "Zoom zurücksetzen", action: #selector(resetZoom), input: "0"),
            UIKeyCommand(title: "Kamera schliessen", action: #selector(close), input: UIKeyCommand.inputEscape),
        ]
    }
}

extension MainViewController {
    func openDocCam() {
        if let open = topController() as? DocCamViewController { open.close(); return }
        DocCam.requestAccess { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                let a = UIAlertController(title: "Kamera nicht erlaubt",
                                          message: "Klassentakt darf die Kamera nicht benutzen. Du kannst das in den Einstellungen ändern.",
                                          preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
                a.addAction(UIAlertAction(title: "Einstellungen", style: .default) { _ in
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                })
                self.topController().present(a, animated: true)
                return
            }
            let vc = DocCamViewController()
            vc.host = self
            vc.modalPresentationStyle = .fullScreen
            self.topController().present(vc, animated: true)
        }
    }
}
