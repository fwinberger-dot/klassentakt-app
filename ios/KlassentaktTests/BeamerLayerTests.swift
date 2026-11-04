import XCTest
@testable import Klassentakt

final class BeamerTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testRunPauseResumeDone() {
        var t = BeamerTimer()
        XCTAssertEqual(t.state(t0), .idle)
        t.start(300, t0)
        XCTAssertEqual(t.state(t0.addingTimeInterval(10)), .running)
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(10)), 290, accuracy: 0.001)
        t.pause(t0.addingTimeInterval(100))
        XCTAssertEqual(t.state(t0.addingTimeInterval(500)), .paused)
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(500)), 200, accuracy: 0.001)
        t.resume(t0.addingTimeInterval(1000))
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(1100)), 100, accuracy: 0.001)
        XCTAssertEqual(t.state(t0.addingTimeInterval(1200)), .done)
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(1300)), 0)
        t.reset()
        XCTAssertEqual(t.state(t0), .idle)
    }

    func testToggle() {
        var t = BeamerTimer()
        t.toggle(60, t0)
        XCTAssertEqual(t.state(t0), .running)
        t.toggle(60, t0.addingTimeInterval(20))
        XCTAssertEqual(t.state(t0.addingTimeInterval(20)), .paused)
        t.toggle(60, t0.addingTimeInterval(30))
        XCTAssertEqual(t.state(t0.addingTimeInterval(30)), .running)
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(30)), 40, accuracy: 0.001)
        // Abgelaufen → Toggle startet neu
        t.toggle(60, t0.addingTimeInterval(500))
        XCTAssertEqual(t.remaining(t0.addingTimeInterval(500)), 60, accuracy: 0.001)
    }

    func testPauseOnlyWhenRunning() {
        var t = BeamerTimer()
        t.pause(t0)
        XCTAssertEqual(t.state(t0), .idle)
        t.resume(t0)
        XCTAssertEqual(t.state(t0), .idle)
    }

    func testFormat() {
        XCTAssertEqual(BeamerTimer.format(300), "5:00")
        XCTAssertEqual(BeamerTimer.format(59.2), "1:00")
        XCTAssertEqual(BeamerTimer.format(61), "1:01")
        XCTAssertEqual(BeamerTimer.format(0), "0:00")
    }
}

final class QuietClassifierTests: XCTestCase {
    func feed(_ q: inout QuietClassifier, _ db: Double, _ n: Int = 30) -> QuietLevel {
        var l = q.level
        for _ in 0..<n { l = q.feed(db) }
        return l
    }

    func testLevels() {
        var q = QuietClassifier()
        XCTAssertEqual(feed(&q, -60), .green)
        XCTAssertEqual(feed(&q, q.yellowAt + 2), .yellow)
        XCTAssertEqual(feed(&q, q.redAt + 2), .red)
        XCTAssertEqual(feed(&q, -70), .green)
    }

    func testHysteresisKeepsYellow() {
        var q = QuietClassifier()
        _ = feed(&q, q.yellowAt + 2)
        XCTAssertEqual(q.level, .yellow)
        // knapp unter der Schwelle bleibt gelb (kein Flackern)
        XCTAssertEqual(feed(&q, q.yellowAt - 1), .yellow)
        XCTAssertEqual(feed(&q, q.yellowAt - QuietClassifier.hysteresis - 1), .green)
    }

    func testSensitivityMovesThresholds() {
        var hi = QuietClassifier(); hi.sensitivity = 1
        var lo = QuietClassifier(); lo.sensitivity = 0
        XCTAssertLessThan(hi.yellowAt, lo.yellowAt)
        XCTAssertEqual(hi.redAt - hi.yellowAt, 10)
    }

    func testIgnoresNonFinite() {
        var q = QuietClassifier()
        XCTAssertEqual(q.feed(-.infinity), .green)
        XCTAssertEqual(q.feed(.nan), .green)
    }

    func testOrdering() {
        XCTAssertLessThan(QuietLevel.green, .red)
        XCTAssertEqual(QuietLevel.yellow.name, "gelb")
    }
}
