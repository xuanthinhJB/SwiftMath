import XCTest
@testable import SwiftMath

/// Notation from secondary-school textbooks: arcs (\overset{\frown}{AB}), similar triangles
/// (\backsim) and accented text such as Vietnamese.
final class TextbookNotationTests: XCTestCase {

    var font: MTFont!

    override func setUp() {
        super.setUp()
        font = MTFontManager().termesFont(withSize: 20)
    }

    private func build(_ latex: String) throws -> MTMathList {
        var error: NSError?
        let list = MTMathListBuilder.build(fromString: latex, error: &error)
        XCTAssertNil(error, "\(latex): \(error?.localizedDescription ?? "")")
        return try XCTUnwrap(list)
    }

    func testBacksimIsARelation() throws {
        let list = try build("\\triangle ABC \\backsim \\triangle DEF")
        let relation = try XCTUnwrap(list.atoms.first { $0.type == .relation })
        XCTAssertEqual(relation.nucleus, "\u{223D}")
    }

    func testFrownAndSmileAreSymbols() throws {
        XCTAssertEqual(try build("\\frown").atoms.first?.nucleus, "\u{2322}")
        XCTAssertEqual(try build("\\smile").atoms.first?.nucleus, "\u{2323}")
    }

    func testOversetFrownIsAnArc() throws {
        for latex in ["\\overset{\\frown}{AB}", "\\stackrel{\\frown}{AB}", "\\overparen{AB}",
                      "\\wideparen{AB}"] {
            let accent = try XCTUnwrap(try build(latex).atoms.first as? MTAccent, latex)
            XCTAssertEqual(accent.nucleus, "\u{23DC}", latex)
            XCTAssertTrue(accent.isWide, latex)
            XCTAssertEqual(accent.innerList?.atoms.map(\.nucleus), ["A", "B"], latex)
        }
    }

    func testOversetWithAnythingElseIsAnError() {
        var error: NSError?
        let list = MTMathListBuilder.build(fromString: "\\overset{x}{AB}", error: &error)
        XCTAssertNil(list)
        XCTAssertEqual(error?.code, MTParseErrors.invalidCommand.rawValue)
    }

    func testArcStretchesOverItsContent() throws {
        for content in ["AB", "ABCD"] {
            let list = try build("\\overset{\\frown}{\(content)}")
            let line = try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: .display))
            let display = try XCTUnwrap(line.subDisplays.first as? MTAccentDisplay)
            let accentee = try XCTUnwrap(display.accentee)
            let arc = try XCTUnwrap(display.accent)
            XCTAssertGreaterThanOrEqual(arc.width, accentee.width * 0.9, content)
            XCTAssertGreaterThan(arc.position.y, 0, "\(content): the arc sits above the letters")
        }
    }

    func testAccentedTextIsKept() throws {
        let list = try build("\\text{Vậy đường cao}")
        let text = list.atoms.map(\.nucleus).joined()
        for letter in ["ậ", "đ", "ư", "ờ"] {
            XCTAssertTrue(text.contains(letter), "\(letter) dropped from \(text)")
        }
    }
}
