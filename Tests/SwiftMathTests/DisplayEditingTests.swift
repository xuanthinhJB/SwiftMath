import XCTest
@testable import SwiftMath

/// closestIndex(to:) and caretPosition(for:), the hit-testing a math editor needs. Points are
/// taken from the displays' own bounds rather than fixed pixels, so the tests hold whatever
/// the font metrics are.
final class DisplayEditingTests: XCTestCase {

    var font: MTFont!

    override func setUp() {
        super.setUp()
        font = MTFontManager().termesFont(withSize: 20)
    }

    private func display(_ latex: String) throws -> MTMathListDisplay {
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: latex))
        return try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: .display))
    }

    private func index(_ location: Int) -> MTMathListIndex { MTMathListIndex(level0Index: location) }

    private func index(_ location: Int, _ type: MTMathListIndex.MTMathListSubIndexType, _ sub: Int) -> MTMathListIndex {
        MTMathListIndex(at: location, with: index(sub), type: type)
    }

    /// Fraction parts and scripts are positioned in the coordinates of the line holding them.
    private func center(_ display: MTDisplay?) throws -> CGPoint {
        let bounds = try XCTUnwrap(display).displayBounds()
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func testRegularLineFollowsTheCaretPositions() throws {
        let line = try display("4+2")
        let carets = try (0...3).map { try XCTUnwrap(line.caretPosition(for: index($0))).x }
        XCTAssertEqual(carets, carets.sorted(), "caret positions go left to right")
        for y: CGFloat in [-20, 0, 8, 40] {  // the height does not matter on one line
            XCTAssertEqual(line.closestIndex(to: CGPoint(x: -10, y: y)), index(0))
            XCTAssertEqual(line.closestIndex(to: CGPoint(x: line.width + 10, y: y)), index(3))
            for i in 0...2 {  // just right of caret i, i.e. at the start of atom i
                XCTAssertEqual(line.closestIndex(to: CGPoint(x: carets[i] + 1, y: y)), index(i), "atom \(i) at y \(y)")
            }
        }
    }

    func testFractionHasNumeratorAndDenominator() throws {
        let line = try display("\\frac{3}{2}")
        let fraction = try XCTUnwrap(line.subDisplays.first as? MTFractionDisplay)
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: -10, y: 0)), index(0))
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: line.width + 10, y: 0)), index(1))
        let numerator = try center(fraction.numerator)
        let denominator = try center(fraction.denominator)
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: numerator.x - 1, y: numerator.y))?.subIndexType, .numerator)
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: denominator.x - 1, y: denominator.y))?.subIndexType, .denominator)
    }

    func testFractionAfterOtherAtoms() throws {
        let line = try display("1+\\frac{3}{2}")
        let fraction = try XCTUnwrap(line.subDisplays.compactMap { $0 as? MTFractionDisplay }.first)
        let numerator = try center(fraction.numerator)
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: fraction.numerator!.displayBounds().minX + 1, y: numerator.y)),
                       index(2, .numerator, 0))
    }

    func testSuperscript() throws {
        let line = try display("2^3")
        let script = try XCTUnwrap(line.subDisplays.compactMap { $0 as? MTMathListDisplay }.first { $0.type == .superscript })
        XCTAssertEqual(line.closestIndex(to: try center(script))?.subIndexType, .superscript)
        XCTAssertEqual(line.closestIndex(to: CGPoint(x: line.width + 10, y: 0)), index(1))
    }

    func testRadicand() throws {
        let line = try display("\\sqrt{x+1}")
        let radical = try XCTUnwrap(line.subDisplays.first as? MTRadicalDisplay)
        let inside = try center(radical.radicand)
        XCTAssertEqual(line.closestIndex(to: inside)?.subIndexType, .radicand)
    }

    func testEveryHitHasACaret() throws {
        for latex in ["4+2", "\\frac{3}{2}", "1+\\frac{a}{b+c}", "2^3", "x_1+x_2", "\\sqrt{x+1}", "AB^2=BC\\cdot CH"] {
            let line = try display(latex)
            for x in stride(from: -5, through: line.width + 5, by: 2) {
                for y: CGFloat in [-15, -5, 0, 5, 15] {
                    let point = CGPoint(x: x, y: y)
                    let hit = try XCTUnwrap(line.closestIndex(to: point), "\(latex) at \(point)")
                    XCTAssertNotNil(line.caretPosition(for: hit), "\(latex): no caret for \(hit) at \(point)")
                }
            }
        }
    }
}
