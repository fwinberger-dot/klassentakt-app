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
/// Verschiebbar. Beim Spiegeln nur noch der Schalter (das iPad-Bild ist ja schon am Beamer).
final class BeamerPiP: UIView {
    private let live = UIView()
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
        liveHeight = live.heightAnchor.constraint(equalToConstant: Self.liveSize.height)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            live.widthAnchor.constraint(equalToConstant: Self.liveSize.width),
            liveHeight,
        ])
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Zustand übernehmen (Modus, Screen offen?) und das Live-Bild starten oder anhalten.
    func refresh() {
        let b = Beamer.shared
        isHidden = !b.isExternalConnected
        mode.selectedSegmentIndex = b.mode == .extend ? 0 : 1
        let extend = b.mode == .extend
        live.isHidden = !extend
        caption.isHidden = !extend
        caption.text = b.screenWebView == nil ? "Beamer · antippen öffnet den Screen" : "Beamer · antippen zum Steuern"
        screenBtn.isHidden = extend || b.screenWebView == nil
        mirror?.stop()
        mirror = nil
        if extend, !isHidden { mirror = LiveMirror(source: b.externalController.view, target: live, fps: 8) }
        superview?.layoutIfNeeded()
        keepInside()
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
