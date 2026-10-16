import XCTest
@testable import SwiftMath

/// MTMathEditor: what a math keyboard and the formula gallery do to a formula.
final class MathEditorTests: XCTestCase {

    private func editor(_ latex: String = "") throws -> MTMathEditor {
        try XCTUnwrap(MTMathEditor(latex: latex), latex)
    }

    private func type(_ editor: MTMathEditor, _ keys: String...) {
        for key in keys { editor.insert(key) }
    }

    func testTypingCharactersAndCommands() throws {
        let e = try editor()
        type(e, "x", "+", "1", "\\le", "3")
        XCTAssertEqual(e.latex, "x+1\\leq 3")
        XCTAssertFalse(e.isEmpty)
    }

    func testUnicodeKeysBecomeCommands() throws {
        let e = try editor()
        type(e, "∠", "A", "=", "9", "0", "°")
        XCTAssertTrue(e.latex.hasPrefix("\\angle A=90"), e.latex)
    }

    func testExponentThenOut() throws {
        let e = try editor()
        type(e, "x", "^", "2")
        XCTAssertEqual(e.caret.innermostType, .superscript)
        e.moveRight()  // out of the exponent
        type(e, "+", "1")
        XCTAssertEqual(e.latex, "x^{2}+1")
    }

    func testCaretPressedAgainLeavesTheExponent() throws {
        let e = try editor()
        type(e, "x", "^", "2", "^", "y")
        XCTAssertEqual(e.latex, "x^{2}y")
    }

    func testSlashMakesAFractionOfTheNumberBefore() throws {
        let e = try editor()
        type(e, "1", "2", "/", "5")
        XCTAssertEqual(e.latex, "\\frac{12}{5}")
        let empty = try editor()
        type(empty, "/")
        XCTAssertEqual(empty.caret.innermostType, .numerator, "nothing before: start in the numerator")
        type(empty, "a")
        empty.moveRight()  // to the denominator's slot
        type(empty, "b")
        XCTAssertEqual(empty.latex, "\\frac{a}{b}")
    }

    func testARelationInADenominatorGoesAfterTheFraction() throws {
        let e = try editor()
        type(e, "1", "/", "2", "=", "x")
        XCTAssertEqual(e.latex, "\\frac{1}{2}=x")
    }

    func testRoots() throws {
        let e = try editor()
        type(e, "\\sqrt", "2")
        XCTAssertEqual(e.latex, "\\sqrt{2}")
        let n = try editor()
        type(n, "\\nthroot", "3")
        n.moveRight()
        type(n, "8")
        XCTAssertEqual(n.latex, "\\sqrt[3]{8}")
    }

    func testTemplatesGoToTheirFirstSlotAndTakeTheTermBefore() throws {
        let e = try editor()
        type(e, "x")
        XCTAssertTrue(e.insertTemplate("\\frac{#@}{#?}"))
        XCTAssertEqual(e.caret.innermostType, .denominator)
        type(e, "2")
        XCTAssertEqual(e.latex, "\\frac{x}{2}")

        let power = try editor()
        type(power, "a", "b")
        power.insertTemplate("#@^{#?}")
        type(power, "3")
        // SwiftMath flattens {ab}: the exponent goes on b, as when typing ab then ^.
        XCTAssertEqual(power.latex, "ab^{3}")
    }

    func testGeometryTemplatesAreEditableInside() throws {
        let angle = try editor()
        angle.insertTemplate("\\widehat{#?}")
        XCTAssertEqual(angle.caret.innermostType, .innerList)
        type(angle, "A", "B", "C")
        XCTAssertEqual(angle.latex, "\\widehat{ABC}")

        let arc = try editor()
        arc.insertTemplate("\\overset{\\frown}{#?}")
        type(arc, "A", "B")
        XCTAssertEqual(arc.latex, "\\overset{\\frown}{AB}", "an arc in the form KaTeX reads")

        let vector = try editor()
        vector.insertTemplate("\\overrightarrow{#?}")
        type(vector, "A", "B")
        XCTAssertEqual(vector.latex, "\\overrightarrow{AB}")

        let segment = try editor()
        segment.insertTemplate("\\overline{#?}")
        type(segment, "A", "B")
        XCTAssertEqual(segment.latex, "\\overline{AB}")
    }

    func testBackspaceEntersStructuresAndRemovesThemOnlyWhenEmpty() throws {
        let e = try editor("\\frac{1}{2}")
        e.deleteBackward()  // into the denominator
        XCTAssertEqual(e.caret.innermostType, .denominator)
        XCTAssertEqual(e.latex, "\\frac{1}{2}", "nothing deleted yet")
        e.deleteBackward()  // the 2
        e.deleteBackward()  // at the denominator's start: back to the numerator
        XCTAssertEqual(e.caret.innermostType, .numerator)
        e.deleteBackward()  // the 1
        e.deleteBackward()  // an empty fraction goes
        XCTAssertEqual(e.latex, "")
        XCTAssertTrue(e.isEmpty)
    }

    func testBackspaceInAnEmptyExponentRemovesIt() throws {
        let e = try editor("x^{2}")
        e.deleteBackward()  // into the exponent
        e.deleteBackward()  // the 2
        e.deleteBackward()  // the empty exponent goes
        XCTAssertEqual(e.latex, "x")
        type(e, "+")
        XCTAssertEqual(e.latex, "x+", "the caret is after x")
    }

    func testCaretWalksThroughEveryPart() throws {
        let e = try editor("\\frac{a}{b}")
        e.moveToEnd()
        var seen: [MTMathListIndex.MTMathListSubIndexType] = []
        for _ in 0..<10 {
            e.moveLeft()
            seen.append(e.caret.innermostType)
        }
        XCTAssertTrue(seen.contains(.numerator) && seen.contains(.denominator), "\(seen)")
        XCTAssertEqual(e.caret, MTMathListIndex(level0Index: 0), "stops at the start")
    }

    func testLoadingKeepsTheFormula() throws {
        for latex in ["\\frac{a}{b}+\\sqrt{x}", "x^{2}+y_{1}", "\\widehat{ABC}=60^{\\circ }", "\\overset{\\frown}{AB}"] {
            XCTAssertEqual(try editor(latex).latex, latex)
        }
        XCTAssertEqual(try editor("\\dfrac{1}{2}").latex, "\\frac{1}{2}")
        XCTAssertEqual(try editor("\\left(x+1\\right)^{2}").latex, "(x+1)^{2}")
    }

    func testTablesAreEditedAsLatex() {
        XCTAssertNil(MTMathEditor(latex: "\\begin{cases}x=1\\\\y=2\\end{cases}"))
        XCTAssertNil(MTMathEditor(latex: "\\frac{"))
    }

    func testTheSlotAtTheCaretIsDrawnBlack() throws {
        let e = try editor()
        e.insertTemplate("\\frac{#?}{#?}")
        let numerator = (e.mathList.atoms.first as? MTFraction)?.numerator?.atoms.first
        let denominator = (e.mathList.atoms.first as? MTFraction)?.denominator?.atoms.first
        XCTAssertEqual(numerator?.nucleus, "\u{25A0}")
        XCTAssertEqual(denominator?.nucleus, "\u{25A1}")
    }

    func testTappingInsideAnAccentPutsTheCaretThere() throws {
        let e = try editor("\\widehat{ABC}+1")
        let font = MTFontManager().termesFont(withSize: 20)
        let line = try XCTUnwrap(MTTypesetter.createLineForMathList(e.mathList, font: font, style: .display))
        let accent = try XCTUnwrap(line.subDisplays.first as? MTAccentDisplay)
        let inner = try XCTUnwrap(accent.accentee).displayBounds()
        let index = try XCTUnwrap(line.closestIndex(to: CGPoint(x: inner.midX, y: inner.midY)))
        XCTAssertEqual(index.subIndexType, .innerList)
        e.moveCaret(to: index)
        type(e, "D")
        XCTAssertTrue(e.latex.hasPrefix("\\widehat{AB"), e.latex)
        XCTAssertTrue(e.latex.contains("D"), e.latex)
    }
}
