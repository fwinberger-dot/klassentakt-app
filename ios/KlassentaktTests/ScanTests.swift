import XCTest
import UIKit
@testable import Klassentakt

final class ScanTests: XCTestCase {
    func testPageOrientation() {
        XCTAssertEqual(ScanFormat.pageSize(for: CGSize(width: 1000, height: 1400)), ScanFormat.a4)
        XCTAssertEqual(ScanFormat.pageSize(for: CGSize(width: 1400, height: 1000)).width, ScanFormat.a4.height)
    }

    func testFitKeepsAspectAndStaysInside() {
        let page = ScanFormat.a4
        let r = ScanFormat.fit(CGSize(width: 2000, height: 1000), in: page)
        XCTAssertEqual(r.width / r.height, 2, accuracy: 0.001)
        XCTAssertTrue(CGRect(origin: .zero, size: page).contains(r))
        XCTAssertEqual(r.midX, page.width / 2, accuracy: 0.001)
        XCTAssertEqual(ScanFormat.fit(.zero, in: page), .zero)
    }

    func testScaledLimitsLongSide() {
        XCTAssertEqual(ScanFormat.scaled(CGSize(width: 4400, height: 2200)), CGSize(width: 2200, height: 1100))
        XCTAssertEqual(ScanFormat.scaled(CGSize(width: 800, height: 600)), CGSize(width: 800, height: 600))
    }

    func testFilesFromPages() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let pdf = ScanFormat.files([img, img], as: .pdf, date: date)
        XCTAssertEqual(pdf.count, 1)
        XCTAssertEqual(pdf[0].type, "application/pdf")
        XCTAssertTrue(pdf[0].data.starts(with: Array("%PDF".utf8)))
        XCTAssertTrue(pdf[0].name.hasPrefix("Scan ") && pdf[0].name.hasSuffix(".pdf"))

        let jpgs = ScanFormat.files([img, img], as: .image, date: date)
        XCTAssertEqual(jpgs.map(\.type), ["image/jpeg", "image/jpeg"])
        XCTAssertTrue(jpgs[1].name.hasSuffix("(2).jpg"))
        XCTAssertFalse(ScanFormat.files([img], as: .image, date: date)[0].name.contains("("))
    }

    func testTempFileNameIsSafe() {
        let f = OutFile(data: Data([1, 2, 3]), name: "a/b:c.pdf", type: "application/pdf")
        let u = f.writeTemp()
        XCTAssertEqual(u?.lastPathComponent, "a-b.c.pdf")
        XCTAssertEqual(try? Data(contentsOf: u!), Data([1, 2, 3]))
    }
}
