import UIKit

/// Beamer-Modus, während der Nutzung umschaltbar (kein Dialog beim Verbinden).
/// - erweitern: Beamer zeigt den Classroom Screen, das iPad den Planer mit Bild im Bild.
/// - spiegeln: Beamer zeigt das iPad-Bild 1:1. Das echte Spiegeln von iPadOS lässt sich zur Laufzeit
///   nicht zurück auf «erweitern» schalten, darum spiegelt die App selbst (Live-Bild ihres Fensters).
enum BeamerMode: String {
    case extend = "erweitern"
    case mirror = "spiegeln"

    var title: String { self == .extend ? "Erweitern" : "Spiegeln" }

    static func control(_ current: BeamerMode, id: String, onChange: @escaping (BeamerMode) -> Void) -> UISegmentedControl {
        let s = UISegmentedControl(items: [BeamerMode.extend.title, BeamerMode.mirror.title])
        s.selectedSegmentIndex = current == .extend ? 0 : 1
        s.accessibilityIdentifier = id
        s.addAction(UIAction { [weak s] _ in onChange(s?.selectedSegmentIndex == 1 ? .mirror : .extend) }, for: .valueChanged)
        return s
    }
}

/// Live-Bild einer View in einer anderen (Beamer ↔ iPad). Ein Screen, ein Zustand – nur das Bild wird kopiert.
/// snapshotView(afterScreenUpdates: false) holt das fertige Bild vom Render-Server, auch von WKWebView.
final class LiveMirror {
    private weak var source: UIView?
    private weak var target: UIView?
    private var link: CADisplayLink?
    private var shot: UIView?

    private let fps: Int
    private var observers: [NSObjectProtocol] = []

    init(source: UIView, target: UIView, fps: Int) {
        self.source = source
        self.target = target
        self.fps = fps
        let l = CADisplayLink(target: Tick(self), selector: #selector(Tick.fire))
        l.add(to: .main, forMode: .common)
        link = l
        throttle()
        let nc = NotificationCenter.default
        for n in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.throttle() })
        }
    }

    deinit { stop() }

    /// Bildrate nach Wärme und Stromsparmodus: warm oder Stromsparen → halb, sehr heiss → 4 Bilder/s.
    static func throttled(_ fps: Int, thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Int {
        var f = fps
        if thermal == .serious || lowPower { f = fps / 2 }
        if thermal == .critical { f = 4 }
        return max(4, min(f, fps))
    }

    private func throttle() {
        let p = ProcessInfo.processInfo
        let f = Self.throttled(fps, thermal: p.thermalState, lowPower: p.isLowPowerModeEnabled)
        // Im UI-Test (langsamer CI-Simulator) knapp halten, sonst wird die App nie «ruhig» für XCUITest.
        link?.preferredFramesPerSecond = TestMode.on ? min(f, 5) : f
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        link?.invalidate()
        link = nil
        shot?.removeFromSuperview()
        shot = nil
    }

    /// Seitenverhältnis behalten, mittig, Rand schwarz.
    static func fit(_ size: CGSize, into box: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(box.width / size.width, box.height / size.height)
    }

    /// Angehalten: letztes Bild bleibt stehen (z.B. solange ein Bearbeiten-Popup offen ist).
    var paused = false

    fileprivate func tick() {
        guard !paused, let s = source, let t = target, s.window != nil, !t.isHidden,
              let v = s.snapshotView(afterScreenUpdates: false) else { return }
        let k = Self.fit(v.bounds.size, into: t.bounds.size)
        v.isUserInteractionEnabled = false
        v.transform = CGAffineTransform(scaleX: k, y: k)
        v.center = CGPoint(x: t.bounds.midX, y: t.bounds.midY)
        t.addSubview(v)
        shot?.removeFromSuperview()
        shot = v
    }

    /// CADisplayLink hält sein Ziel fest → kleiner Vermittler, damit LiveMirror freigegeben werden kann.
    private final class Tick: NSObject {
        weak var mirror: LiveMirror?
        init(_ m: LiveMirror) { mirror = m }
        @objc func fire() { mirror?.tick() }
    }
}

/// Bild im Bild auf dem iPad (Planer): zeigt live, was am Beamer läuft. Antippen = Screen gross zum Steuern.
/// Verschiebbar, Grösse frei (zwei Finger oder Griff oben links, wird gemerkt), «–» blendet es aus
/// (zurück über den Griff am rechten Rand oder ⌘⇧B). Beim Spiegeln nur noch der Schalter.
final class BeamerPiP: UIView {
    private let live = UIView()
    private let hideBtn = UIButton(type: .system)
    private let grip = UIImageView(image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"))
    private var liveWidth: NSLayoutConstraint!
    private var pinchStart: CGFloat = 0
    /// Ausgeblendet mit «–» (gilt bis zum Zurückholen, auch über Neustarts).
    private(set) var minimized = UserDefaults.standard.bool(forKey: BeamerPiP.minimizedKey)
    var onMinimizedChange: (() -> Void)?

    static let widthKey = "ktPiPBreite", minimizedKey = "ktPiPAus"
    static let widthRange: ClosedRange<CGFloat> = 200...720
    static func clampWidth(_ w: CGFloat) -> CGFloat { min(max(w, widthRange.lowerBound), widthRange.upperBound).rounded() }
    static var savedWidth: CGFloat {
        let w = CGFloat(UserDefaults.standard.double(forKey: widthKey))
        return w > 0 ? clampWidth(w) : liveSize.width
    }
    private let caption = UILabel()
    private var mode: UISegmentedControl!
    private let screenBtn = UIButton(type: .system)
    private var mirror: LiveMirror?
    private var liveHeight: NSLayoutConstraint!
    weak var host: MainViewController?

    static let liveSize = CGSize(width: 320, height: 180)

    init(host: MainViewController) {
        self.host = host
        super.init(frame: .zero)
        accessibilityIdentifier = "beamerPiP"
        backgroundColor = UIColor(white: 0.1, alpha: 0.92)
        layer.cornerRadius = 16
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        live.backgroundColor = .black
        live.clipsToBounds = true
        live.layer.cornerRadius = 10
        live.accessibilityIdentifier = "pipLive"
        live.isAccessibilityElement = true
        live.accessibilityLabel = "Beamer-Bild. Antippen, um den Screen auf dem iPad zu steuern."
        live.accessibilityTraits = .button
        live.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapLive)))

        hideBtn.setImage(UIImage(systemName: "minus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        hideBtn.tintColor = .white
        hideBtn.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        hideBtn.layer.cornerRadius = 15
        hideBtn.accessibilityIdentifier = "pipHide"
        hideBtn.accessibilityLabel = "Bild im Bild ausblenden"
        hideBtn.translatesAutoresizingMaskIntoConstraints = false
        hideBtn.addAction(UIAction { [weak self] _ in self?.setMinimized(true) }, for: .touchUpInside)

        grip.tintColor = .white
        grip.contentMode = .center
        grip.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        grip.layer.cornerRadius = 15
        grip.isUserInteractionEnabled = true
        grip.accessibilityIdentifier = "pipResize"
        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:))))

        caption.text = "Beamer · antippen zum Steuern"
        caption.textColor = UIColor(white: 1, alpha: 0.8)
        caption.font = .systemFont(ofSize: 12, weight: .semibold)

        mode = BeamerMode.control(Beamer.shared.mode, id: "pipMode") { Beamer.shared.setMode($0) }
        mode.selectedSegmentTintColor = .white
        mode.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        mode.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)

        var c = UIButton.Configuration.filled()
        c.title = "Screen"
        c.cornerStyle = .capsule
        c.baseBackgroundColor = .white
        c.baseForegroundColor = .black
        screenBtn.configuration = c
        screenBtn.accessibilityIdentifier = "pipScreen"
        screenBtn.addAction(UIAction { _ in Beamer.shared.control(true) }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [mode, screenBtn])
        row.spacing = 8
        let stack = UIStackView(arrangedSubviews: [live, caption, row])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let w = Self.savedWidth
        liveHeight = live.heightAnchor.constraint(equalToConstant: w * 9 / 16)
        liveWidth = live.widthAnchor.constraint(equalToConstant: w)
        addSubview(hideBtn)
        addSubview(grip)
        NSLayoutConstraint.activate([
            hideBtn.topAnchor.constraint(equalTo: live.topAnchor, constant: 6),
            hideBtn.trailingAnchor.constraint(equalTo: live.trailingAnchor, constant: -6),
            hideBtn.widthAnchor.constraint(equalToConstant: 30), hideBtn.heightAnchor.constraint(equalToConstant: 30),
            grip.topAnchor.constraint(equalTo: live.topAnchor, constant: 6),
            grip.leadingAnchor.constraint(equalTo: live.leadingAnchor, constant: 6),
            grip.widthAnchor.constraint(equalToConstant: 30), grip.heightAnchor.constraint(equalToConstant: 30),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            liveWidth,
            liveHeight,
        ])
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Zustand übernehmen (Modus, Screen offen?) und das Live-Bild starten oder anhalten.
    func refresh() {
        let b = Beamer.shared
        isHidden = !b.isExternalConnected || minimized
        mode.selectedSegmentIndex = b.mode == .extend ? 0 : 1
        let extend = b.mode == .extend
        live.isHidden = !extend
        grip.isHidden = !extend
        caption.isHidden = !extend
        caption.text = b.screenWebView == nil ? "Beamer · antippen öffnet den Screen" : "Beamer · antippen zum Steuern"
        screenBtn.isHidden = extend || b.screenWebView == nil
        mirror?.stop()
        mirror = nil
        if extend, !isHidden { mirror = LiveMirror(source: b.externalController.view, target: live, fps: 8) }
        superview?.layoutIfNeeded()
        keepInside()
    }

    func setMinimized(_ on: Bool) {
        guard on != minimized else { return }
        minimized = on
        UserDefaults.standard.set(on, forKey: Self.minimizedKey)
        refresh()
        onMinimizedChange?()
    }

    /// Neue Breite (Höhe 16:9); die Ecke unten rechts bleibt stehen.
    private func setWidth(_ w: CGFloat, save: Bool) {
        let nw = Self.clampWidth(w)
        guard nw != liveWidth.constant || save else { return }
        let br = CGPoint(x: frame.maxX, y: frame.maxY)
        liveWidth.constant = nw
        liveHeight.constant = nw * 9 / 16
        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(x: br.x - size.width, y: br.y - size.height, width: size.width, height: size.height)
        if save {
            UserDefaults.standard.set(Double(nw), forKey: Self.widthKey)
            keepInside()
        }
    }

    @objc private func resize(_ g: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let d = g.translation(in: sv)
        g.setTranslation(.zero, in: sv)
        // Griff oben links: nach links/oben ziehen = grösser.
        setWidth(liveWidth.constant - (abs(d.x) > abs(d.y) ? d.x : d.y * 16 / 9), save: g.state == .ended)
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { pinchStart = liveWidth.constant }
        setWidth(pinchStart * g.scale, save: g.state == .ended || g.state == .cancelled)
    }

    @objc private func tapLive() {
        if Beamer.shared.screenWebView == nil { host?.openScreen() } else { Beamer.shared.control(true) }
    }

    @objc private func drag(_ g: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let d = g.translation(in: sv)
        center = CGPoint(x: center.x + d.x, y: center.y + d.y)
        g.setTranslation(.zero, in: sv)
        if g.state == .ended { keepInside() }
    }

    /// Ganz im sichtbaren Bereich halten (nach Verschieben, Drehen, Grössenwechsel).
    func keepInside() {
        guard let sv = superview else { return }
        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let area = sv.bounds.inset(by: sv.safeAreaInsets).insetBy(dx: 12, dy: 12)
        var f = CGRect(origin: frame.origin, size: size)
        if frame.width == 0 { f.origin = CGPoint(x: area.maxX - size.width, y: area.maxY - size.height - 60) }
        f.origin.x = min(max(f.origin.x, area.minX), area.maxX - f.width)
        f.origin.y = min(max(f.origin.y, area.minY), area.maxY - f.height)
        UIView.animate(withDuration: 0.2) { self.frame = f }
    }
}

/// Griff am rechten Rand, solange das Bild im Bild mit «–» ausgeblendet ist. Antippen holt es zurück.
final class PiPHandle: UIButton {
    init() {
        super.init(frame: .zero)
        var c = UIButton.Configuration.filled()
        c.image = UIImage(systemName: "chevron.left")
        c.title = "Beamer"
        c.imagePadding = 4
        c.baseBackgroundColor = UIColor(white: 0.1, alpha: 0.9)
        c.baseForegroundColor = .white
        c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 14)
        configuration = c
        layer.cornerRadius = 14
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        clipsToBounds = true
        accessibilityIdentifier = "pipHandle"
        accessibilityLabel = "Bild im Bild wieder einblenden"
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Leiste über dem Screen auf dem iPad, solange ein Beamer verbunden ist: Modus und «Zum Planer».
final class ScreenBar: UIView {
    private var mode: UISegmentedControl!

    init() {
        super.init(frame: .zero)
        accessibilityIdentifier = "screenBar"
        backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        layer.cornerRadius = 20
        mode = BeamerMode.control(Beamer.shared.mode, id: "screenMode") { Beamer.shared.setMode($0) }
        mode.selectedSegmentTintColor = .white
        mode.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        mode.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        var c = UIButton.Configuration.filled()
        c.title = "Zum Planer"
        c.image = UIImage(systemName: "rectangle.on.rectangle")
        c.imagePadding = 6
        c.cornerStyle = .capsule
        c.baseBackgroundColor = .white
        c.baseForegroundColor = .black
        let back = UIButton(configuration: c)
        back.accessibilityIdentifier = "screenToPlanner"
        back.addAction(UIAction { _ in Beamer.shared.control(false) }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [mode, back])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        isHidden = !Beamer.shared.isExternalConnected
        mode.selectedSegmentIndex = Beamer.shared.mode == .extend ? 0 : 1
    }
}
