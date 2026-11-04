import UIKit
import AVFoundation
import AudioToolbox

extension Notification.Name {
    /// Timer, Ruhe-Ampel, «schwarz» oder Verbindung haben sich geändert.
    static let beamerLayerChanged = Notification.Name("ch.klassentakt.beamerLayerChanged")
}

// MARK: - Timer (Logik, getestet)

/// Countdown der Beamer-Ebene. Rechnet mit Endzeit, damit er im Hintergrund nicht falsch läuft.
struct BeamerTimer {
    enum State: Equatable { case idle, running, paused, done }
    private(set) var duration: TimeInterval = 0
    private(set) var end: Date?
    private(set) var left: TimeInterval = 0
    private(set) var paused = false

    func state(_ now: Date = Date()) -> State {
        if duration <= 0 { return .idle }
        if paused { return .paused }
        if let e = end { return e > now ? .running : .done }
        return .idle
    }

    func remaining(_ now: Date = Date()) -> TimeInterval {
        if paused { return left }
        guard let e = end else { return 0 }
        return max(0, e.timeIntervalSince(now))
    }

    mutating func start(_ seconds: TimeInterval, _ now: Date = Date()) {
        duration = max(1, seconds)
        end = now.addingTimeInterval(duration)
        paused = false
        left = 0
    }

    mutating func pause(_ now: Date = Date()) {
        guard state(now) == .running else { return }
        left = remaining(now)
        paused = true
        end = nil
    }

    mutating func resume(_ now: Date = Date()) {
        guard paused else { return }
        end = now.addingTimeInterval(left)
        paused = false
    }

    mutating func reset() { self = BeamerTimer() }

    /// ⌘⇧T: läuft → Pause, Pause → weiter, sonst neu mit `seconds`.
    mutating func toggle(_ seconds: TimeInterval, _ now: Date = Date()) {
        switch state(now) {
        case .running: pause(now)
        case .paused: resume(now)
        case .idle, .done: start(seconds, now)
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Ruhe-Ampel (Logik, getestet)

enum QuietLevel: Int, Comparable {
    case green, yellow, red
    static func < (a: QuietLevel, b: QuietLevel) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["gruen", "gelb", "rot"][rawValue] }
}

/// Lautstärke (dBFS vom Mikrofon) → Ampel. Geglättet und mit Hysterese, damit sie nicht flackert.
struct QuietClassifier {
    /// 0 = unempfindlich (erst laute Klasse wird rot), 1 = sehr empfindlich.
    var sensitivity: Double = 0.5
    private(set) var smoothed: Double = -60
    private(set) var level: QuietLevel = .green
    static let hysteresis = 3.0

    var yellowAt: Double { -32 + (0.5 - sensitivity) * 20 }
    var redAt: Double { yellowAt + 10 }

    mutating func feed(_ db: Double) -> QuietLevel {
        let v = db.isFinite ? max(-80, min(0, db)) : -80
        smoothed = smoothed * 0.7 + v * 0.3
        let h = Self.hysteresis
        switch level {
        case .green:
            if smoothed >= redAt { level = .red } else if smoothed >= yellowAt { level = .yellow }
        case .yellow:
            if smoothed >= redAt { level = .red } else if smoothed < yellowAt - h { level = .green }
        case .red:
            if smoothed < yellowAt - h { level = .green } else if smoothed < redAt - h { level = .yellow }
        }
        return level
    }

    mutating func reset() { smoothed = -60; level = .green }
}

/// Mikrofonpegel. Nimmt nichts auf (schreibt nach /dev/null), misst nur.
final class NoiseMeter {
    private var recorder: AVAudioRecorder?
    private var tick: Timer?
    var onLevel: ((Double) -> Void)?

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        if TestMode.on { done(true); return }
        let s = AVAudioSession.sharedInstance()
        switch s.recordPermission {
        case .granted: done(true)
        case .denied: done(false)
        default: s.requestRecordPermission { ok in DispatchQueue.main.async { done(ok) } }
        }
    }

    func start() -> Bool {
        if TestMode.on {
            // UI-Test: erfundener Pegel, wird in 6 s laut und wieder leise.
            var t = 0.0
            tick = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                t += 0.2
                self?.onLevel?(-48 + 36 * (0.5 - 0.5 * cos(2 * .pi * t / 12)))
            }
            return true
        }
        let s = AVAudioSession.sharedInstance()
        do {
            // Mischen statt unterbrechen: Musik und Videos im Screen laufen weiter.
            try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay])
            try s.setActive(true)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1]
            let r = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { return false }
            recorder = r
        } catch { return false }
        tick = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let r = self?.recorder else { return }
            r.updateMeters()
            self?.onLevel?(Double(r.averagePower(forChannel: 0)))
        }
        return true
    }

    func stop() {
        tick?.invalidate(); tick = nil
        if TestMode.on { return }
        recorder?.stop(); recorder = nil
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        try? s.setCategory(.soloAmbient)
    }
}

// MARK: - Ebene

/// Eigene Ebene auf dem Beamer: Timer, Ruhe-Ampel, «schwarz». Das iPad ist die Fernbedienung.
final class BeamerLayer {
    private(set) var timer = BeamerTimer()
    private(set) var quietOn = false
    private(set) var quiet = QuietClassifier()
    private let meter = NoiseMeter()
    private var tick: Timer?
    private var rang = false

    /// Zuletzt gewählte Timer-Dauer (Sekunden), Standard 5 Minuten.
    var lastSeconds: TimeInterval {
        get { let v = UserDefaults.standard.double(forKey: "kt.timerSeconds"); return v > 0 ? v : 300 }
        set { UserDefaults.standard.set(newValue, forKey: "kt.timerSeconds") }
    }
    var sensitivity: Double {
        get { UserDefaults.standard.object(forKey: "kt.quietSens") as? Double ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: "kt.quietSens"); quiet.sensitivity = newValue }
    }

    init() {
        quiet.sensitivity = sensitivity
        meter.onLevel = { [weak self] db in
            guard let self = self else { return }
            let before = self.quiet.level
            if self.quiet.feed(db) != before { self.changed() }
        }
    }

    var stateForWeb: [String: Any] {
        let st = timer.state()
        let states: [BeamerTimer.State: String] = [.idle: "idle", .running: "running", .paused: "paused", .done: "done"]
        return ["timer": ["state": states[st] ?? "idle", "remaining": Int(timer.remaining().rounded(.up)), "duration": Int(timer.duration)],
                "quiet": quietOn ? quiet.level.name : false]
    }

    var isActive: Bool { timer.state() != .idle || quietOn }

    // MARK: Timer

    func startTimer(_ seconds: TimeInterval) {
        lastSeconds = seconds
        timer.start(seconds)
        rang = false
        runTick()
        changed()
    }

    func toggleTimer() {
        timer.toggle(lastSeconds)
        if timer.state() == .running { rang = false }
        runTick()
        changed()
    }

    func resetTimer() {
        timer.reset()
        changed()
    }

    /// Steuerung aus der Web-App: send('overlay', {timer: {action, seconds}}).
    func timerAction(_ action: String, seconds: TimeInterval?) {
        switch action {
        case "start": startTimer(seconds ?? lastSeconds)
        case "pause": timer.pause(); changed()
        case "resume": timer.resume(); runTick(); changed()
        case "toggle": toggleTimer()
        case "reset": resetTimer()
        default: break
        }
    }

    private func runTick() {
        guard tick == nil else { return }
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let st = self.timer.state()
            if st == .done && !self.rang {
                self.rang = true
                AudioServicesPlaySystemSound(1005)
            }
            if st != .running { t.invalidate(); self.tick = nil }
            self.changed()
        }
    }

    // MARK: Ruhe-Ampel

    func setQuiet(_ on: Bool, ask: UIViewController?) {
        guard on != quietOn else { return }
        if !on {
            meter.stop()
            quietOn = false
            quiet.reset()
            changed()
            return
        }
        NoiseMeter.requestAccess { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                let a = UIAlertController(title: "Mikrofon nicht erlaubt",
                                          message: "Die Ruhe-Ampel misst nur die Lautstärke und nimmt nichts auf. Erlauben kannst du das Mikrofon in den Einstellungen.",
                                          preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
                a.addAction(UIAlertAction(title: "Einstellungen", style: .default) { _ in
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                })
                ask?.present(a, animated: true)
                self.changed()
                return
            }
            self.quiet.reset()
            self.quietOn = self.meter.start()
            if !self.quietOn { Beamer.shared.host?.toast("Mikrofon ist gerade nicht verfügbar") }
            self.changed()
        }
    }

    private func changed() {
        Beamer.shared.layerChanged()
    }
}

// MARK: - Anzeige auf dem Beamer

final class TimerBadge: PaddingLabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        insets = UIEdgeInsets(top: 14, left: 30, bottom: 14, right: 30)
        font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        textColor = .white
        layer.cornerRadius = 28
        clipsToBounds = true
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ t: BeamerTimer) {
        let st = t.state()
        isHidden = st == .idle
        text = st == .done ? "Zeit!" : BeamerTimer.format(t.remaining())
        backgroundColor = st == .done ? UIColor.systemRed : UIColor(white: 0.05, alpha: st == .paused ? 0.55 : 0.8)
        alpha = st == .paused ? 0.7 : 1
        accessibilityLabel = st == .done ? "Zeit ist um" : "Timer \(text ?? "")"
    }
}

final class QuietLight: UIStackView {
    private let lamps: [UIView] = (0..<3).map { _ in UIView() }
    private let colors: [UIColor] = [.systemRed, .systemYellow, .systemGreen]

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 12
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        backgroundColor = UIColor(white: 0.05, alpha: 0.85)
        layer.cornerRadius = 26
        isHidden = true
        for l in lamps {
            l.layer.cornerRadius = 32
            l.widthAnchor.constraint(equalToConstant: 64).isActive = true
            l.heightAnchor.constraint(equalToConstant: 64).isActive = true
            addArrangedSubview(l)
        }
    }
    required init(coder: NSCoder) { fatalError() }

    func show(_ on: Bool, _ level: QuietLevel) {
        isHidden = !on
        // Reihenfolge oben → unten: rot, gelb, grün
        let active = [QuietLevel.red, .yellow, .green]
        for (i, l) in lamps.enumerated() {
            l.backgroundColor = colors[i].withAlphaComponent(active[i] == level ? 1 : 0.18)
        }
        accessibilityLabel = "Ruhe-Ampel \(level.name)"
    }
}

// MARK: - Fernbedienung auf dem iPad

/// Knopf unten rechts: erscheint, sobald ein Beamer verbunden ist oder Timer/Ampel laufen.
final class BeamerPill: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        var c = UIButton.Configuration.filled()
        c.baseBackgroundColor = UIColor(red: 0.063, green: 0.133, blue: 0.114, alpha: 0.92)
        c.baseForegroundColor = .white
        c.cornerStyle = .capsule
        c.image = UIImage(systemName: "rectangle.on.rectangle")
        c.imagePadding = 8
        c.title = "Beamer"
        configuration = c
        accessibilityHint = "Timer, Ruhe-Ampel und Bildschirm schwarz"
        accessibilityIdentifier = "beamerPill"
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let b = Beamer.shared, l = b.layer
        isHidden = !(b.isExternalConnected || l.isActive || b.isBlack)
        var t = "Beamer"
        if b.isBlack { t += " · schwarz" }
        if l.timer.state() != .idle { t += " · " + (l.timer.state() == .done ? "Zeit!" : BeamerTimer.format(l.timer.remaining())) }
        configuration?.title = t
        configuration?.image = UIImage(systemName: l.quietOn ? "circle.fill" : "rectangle.on.rectangle")
        configuration?.imageColorTransformer = l.quietOn
            ? UIConfigurationColorTransformer { _ in [UIColor.systemGreen, .systemYellow, .systemRed][l.quiet.level.rawValue] }
            : nil
    }
}

final class BeamerRemoteViewController: UIViewController {
    weak var host: MainViewController?
    private let status = UILabel()
    private let timeLabel = UILabel()
    private let startBtn = UIButton(type: .system)
    private let blackBtn = UIButton(type: .system)
    private let screenBtn = UIButton(type: .system)
    private let camBtn = UIButton(type: .system)
    private let quietSwitch = UISwitch()
    private let sens = UISlider()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 380, height: 470)

        let title = UILabel()
        title.text = "Beamer"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        status.font = .systemFont(ofSize: 14)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0

        screenBtn.configuration = .bordered()
        screenBtn.addAction(UIAction { [weak self] _ in self?.host?.run(.screenToggle); self?.later() }, for: .touchUpInside)
        camBtn.configuration = .bordered()
        camBtn.configuration?.title = "Dokumentenkamera"
        camBtn.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) { self?.host?.openDocCam() } }, for: .touchUpInside)
        blackBtn.configuration = .bordered()
        blackBtn.addAction(UIAction { _ in Beamer.shared.toggleBlack() }, for: .touchUpInside)
        let show = row([screenBtn, camBtn])

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        let presets = row([1, 2, 3, 5, 10, 15].map { m in
            let b = UIButton(type: .system)
            b.configuration = .gray()
            b.configuration?.title = "\(m)′"
            b.accessibilityLabel = "\(m) Minuten"
            b.addAction(UIAction { _ in Beamer.shared.layer.startTimer(TimeInterval(m * 60)) }, for: .touchUpInside)
            return b
        })
        startBtn.configuration = .borderedProminent()
        startBtn.addAction(UIAction { _ in Beamer.shared.layer.toggleTimer() }, for: .touchUpInside)
        let reset = UIButton(type: .system)
        reset.configuration = .bordered()
        reset.configuration?.title = "Zurücksetzen"
        reset.addAction(UIAction { _ in Beamer.shared.layer.resetTimer() }, for: .touchUpInside)
        let timerRow = row([timeLabel, startBtn, reset])

        let quietLabel = UILabel()
        quietLabel.text = "Ruhe-Ampel (Mikrofon)"
        quietLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        quietSwitch.accessibilityIdentifier = "quietSwitch"
        quietSwitch.addAction(UIAction { [weak self] _ in
            Beamer.shared.layer.setQuiet(self?.quietSwitch.isOn ?? false, ask: self)
        }, for: .valueChanged)
        sens.minimumValue = 0
        sens.maximumValue = 1
        sens.value = Float(Beamer.shared.layer.sensitivity)
        sens.addAction(UIAction { [weak self] _ in Beamer.shared.layer.sensitivity = Double(self?.sens.value ?? 0.5) }, for: .valueChanged)
        let sensLabel = UILabel()
        sensLabel.text = "Empfindlich"
        sensLabel.font = .systemFont(ofSize: 14)
        sensLabel.textColor = .secondaryLabel
        let note = UILabel()
        note.text = "Die Ampel misst nur die Lautstärke. Es wird nichts aufgenommen oder gespeichert."
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0

        let keys = UIButton(type: .system)
        keys.configuration = .plain()
        keys.configuration?.title = "⌘ Kürzel"
        keys.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) { self?.host?.run(.shortcutsHelp) } }, for: .touchUpInside)
        let head = row([title, UIView(), keys])
        let stack = UIStackView(arrangedSubviews: [
            head, status, section("Zeigt"), show, blackBtn,
            section("Timer"), timerRow, presets,
            row([quietLabel, quietSwitch]), row([sensLabel, sens]), note,
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: blackBtn)
        stack.setCustomSpacing(18, after: presets)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .beamerLayerChanged, object: nil)
        refresh()
    }

    private func later() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() } }

    private func section(_ t: String) -> UILabel {
        let l = UILabel()
        l.text = t.uppercased()
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .secondaryLabel
        return l
    }

    private func row(_ views: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        s.distribution = views.count > 3 ? .fillEqually : .fill
        return s
    }

    @objc private func refresh() {
        let b = Beamer.shared, l = b.layer
        status.text = b.isExternalConnected
            ? "Verbunden. Timer, Ampel und «schwarz» erscheinen auf dem Beamer, das iPad bleibt die Fernbedienung."
            : "Kein Beamer im Modus «erweitern». Timer und Ampel laufen hier auf dem iPad mit."
        screenBtn.configuration?.title = b.screenWebView == nil ? "Classroom Screen" : "Screen schliessen"
        blackBtn.configuration?.title = b.isBlack ? "Wieder zeigen" : "Bildschirm schwarz"
        blackBtn.configuration?.image = UIImage(systemName: b.isBlack ? "eye" : "eye.slash")
        let st = l.timer.state()
        timeLabel.text = st == .idle ? BeamerTimer.format(l.lastSeconds) : st == .done ? "Zeit!" : BeamerTimer.format(l.timer.remaining())
        startBtn.configuration?.title = st == .running ? "Pause" : st == .paused ? "Weiter" : "Start"
        if quietSwitch.isOn != l.quietOn { quietSwitch.setOn(l.quietOn, animated: true) }
    }
}

// MARK: - Einbindung

extension MainViewController {
    func installBeamerPill() {
        let pill = BeamerPill()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addAction(UIAction { [weak self, weak pill] _ in if let p = pill { self?.openBeamerRemote(from: p) } }, for: .touchUpInside)
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        beamerPill = pill
    }

    func openBeamerRemote(from source: UIView? = nil) {
        if let open = topController() as? BeamerRemoteViewController { open.dismiss(animated: true); return }
        let vc = BeamerRemoteViewController()
        vc.host = self
        vc.modalPresentationStyle = .popover
        if let p = vc.popoverPresentationController {
            let v = source ?? beamerPill ?? view!
            p.sourceView = v
            p.sourceRect = v.bounds
        }
        topController().present(vc, animated: true)
    }

    /// Beamer eben verbunden: Hinweis und Auswahl, was er zeigen soll.
    func beamerConnectedPrompt() {
        guard view.window != nil, !(topController() is UIAlertController), TestMode.run == nil else { return }
        let b = Beamer.shared
        let a = UIAlertController(title: "Beamer verbunden",
                                  message: "Was soll der Beamer zeigen? Das iPad bleibt die Fernbedienung (Knopf «Beamer» unten rechts).",
                                  preferredStyle: .alert)
        if b.screenWebView == nil {
            a.addAction(UIAlertAction(title: "Classroom Screen", style: .default) { [weak self] _ in self?.run(.screenToggle) })
        }
        a.addAction(UIAlertAction(title: "Dokumentenkamera", style: .default) { [weak self] _ in self?.openDocCam() })
        a.addAction(UIAlertAction(title: "Bildschirm schwarz", style: .default) { _ in b.setBlack(true) })
        a.addAction(UIAlertAction(title: "Später", style: .cancel))
        topController().present(a, animated: true)
    }
}
