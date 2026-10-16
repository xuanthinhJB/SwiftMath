//
//  MTMathEditor.swift
//
//  The model of a visual formula editor: a math list, the caret (an MTMathListIndex) and the
//  edits a math keyboard makes. No UI: a view draws `mathList` with MTTypesetter and moves the
//  caret with MTDisplay.closestIndex(to:).
//
//  The key handling follows MathEditor's MTEditableMathLabel (MIT, Kostub Deshmukh).
//

import Foundation

public final class MTMathEditor {
    /// The formula. Empty slots are `.placeholder` atoms; the one at the caret is drawn black.
    public private(set) var mathList: MTMathList
    /// Where the next atom goes. On an empty slot it points at the slot, which typing replaces.
    public private(set) var caret: MTMathListIndex

    /// Starts from LaTeX; nil when SwiftMath cannot read it (edit it as LaTeX instead).
    public init?(latex: String = "") {
        var error: NSError?
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            mathList = MTMathList()
        } else {
            guard let list = MTMathListBuilder.build(fromString: Self.editable(trimmed), error: &error), error == nil,
                  !Self.containsUneditable(list) else { return nil }
            mathList = list
        }
        caret = MTMathListIndex(level0Index: mathList.atoms.count)
        normalizeCaret()
    }

    public var isEmpty: Bool { mathList.atoms.allSatisfy(Self.isEmptySlot) }

    /// The formula as LaTeX, without the empty slots.
    public var latex: String {
        MTMathListBuilder.mathListToString(Self.withoutSlots(mathList)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Typing

    /// One key of the math keyboard:
    /// - a character (`x`, `2`, `+`, `≤`, `π`…) or a LaTeX command (`\le`, `\pi`, `\perp`…);
    /// - `^` exponent, `_` subscript, `/` fraction (the number or letters before it become
    ///   the numerator), `\sqrt` square root, `\nthroot` root with a degree;
    /// - `()` and `||`: a pair with the caret inside.
    public func insert(_ key: String) {
        switch key {
        case "^": exponentOrSubscript(.superscript)
        case "_": exponentOrSubscript(.ssubscript)
        case "/": fraction()
        case "\\sqrt", "√": insertTemplate("\\sqrt{#?}")
        case "\\nthroot", "∛": insertTemplate("\\sqrt[#?]{#?}")
        case "()": insertTemplate("(#?)")
        case "||": insertTemplate("|#?|")
        default:
            if key.hasPrefix("\\") {
                if let atom = MTMathAtomFactory.atom(forLatexSymbol: String(key.dropFirst())) {
                    place(atom)
                } else {
                    insertTemplate(key)
                }
            } else {
                for character in key {
                    if let atom = Self.atom(for: character) { place(atom) }
                }
            }
        }
        normalizeCaret()
    }

    /// A template from the formula gallery: `#?` is an empty slot and `#@` takes the term just
    /// before the caret (or becomes a slot). The caret goes to the first slot. Returns false when
    /// SwiftMath cannot read the template.
    @discardableResult
    public func insertTemplate(_ template: String) -> Bool {
        guard let (list, position) = mathList.list(containing: caret) else { return false }
        var latex = Self.editable(template)
        var start = position
        if latex.contains("#@") {
            // The term before the caret goes into the template (x → x², 3 → ³⁄…).
            let taken = Self.termBefore(position, in: list)
            let term = MTMathList()
            for atom in list.atoms[taken] { term.add(atom) }
            let source = taken.isEmpty ? "\\square " : "{" + MTMathListBuilder.mathListToString(term) + "}"
            latex = latex.replacingOccurrences(of: "#@", with: source)
            if !taken.isEmpty {
                list.removeAtoms(in: taken.lowerBound...(taken.upperBound - 1))
                start = taken.lowerBound
            }
        }
        latex = latex.replacingOccurrences(of: "#?", with: "\\square ")
        var error: NSError?
        guard let parsed = MTMathListBuilder.build(fromString: latex, error: &error), error == nil else { return false }
        if start < list.atoms.count, Self.isEmptySlot(list.atoms[start]) { list.removeAtom(at: start) }
        for (offset, atom) in parsed.atoms.enumerated() { list.insert(atom, at: start + offset) }
        // To the first empty slot of what was inserted, else just after it.
        let first = caret.replacingInnermost(with: start)
        let end = caret.replacingInnermost(with: start + parsed.atoms.count)
        let positions = caretPositions
        if let from = positions.firstIndex(of: first),
           let slot = positions[from...].first(where: { position in
               position != end && mathList.atom(at: position).map(Self.isEmptySlot) == true
               && Self.isInside(position, from: first, to: end)
           }) {
            caret = slot
        } else {
            caret = end
        }
        normalizeCaret()
        return true
    }

    /// Backspace. Deletes the atom before the caret; a structure with content is entered
    /// rather than deleted, and at the start of a part an empty structure is removed (else the
    /// caret moves back), so nothing typed is lost by one key.
    public func deleteBackward() {
        guard let (list, position) = mathList.list(containing: caret) else { return }
        if position > 0 {
            let atom = list.atoms[position - 1]
            if !Self.isEmptySlot(atom) && atom.editableSubLists.contains(where: { !Self.isEmpty($0.1) }) {
                moveLeft()  // into the fraction, root, script… from its end
                return
            }
            list.removeAtom(at: position - 1)
            caret = caret.replacingInnermost(with: position - 1)
            fillIfEmpty(list)
            normalizeCaret()
            return
        }
        // At the start of a part.
        guard let parentIndex = caret.parent, let owner = mathList.atom(at: parentIndex),
              let (parentList, ownerPosition) = mathList.list(containing: parentIndex) else { return }
        let part = caret.innermostType
        if part == .superscript || part == .ssubscript {
            guard Self.isEmpty(owner.subList(part)) else { moveLeft(); return }
            if part == .superscript { owner.superScript = nil } else { owner.subScript = nil }
            if Self.isEmptySlot(owner) && owner.superScript == nil && owner.subScript == nil {
                parentList.removeAtom(at: ownerPosition)
                caret = parentIndex
                fillIfEmpty(parentList)
            } else {
                caret = parentIndex.next
            }
        } else if owner.editableSubLists.allSatisfy({ Self.isEmpty($0.1) }) {
            parentList.removeAtom(at: ownerPosition)
            caret = parentIndex
            fillIfEmpty(parentList)
        } else {
            moveLeft()
        }
        normalizeCaret()
    }

    // MARK: - Moving the caret

    /// Every place the caret can be, in reading order (inside structures too).
    public var caretPositions: [MTMathListIndex] { Self.positions(in: mathList) { $0 } }

    public func moveLeft() {
        let positions = caretPositions
        if let current = positions.firstIndex(of: caret), current > 0 { caret = positions[current - 1] }
        normalizeCaret()
    }

    public func moveRight() {
        let positions = caretPositions
        if let current = positions.firstIndex(of: caret), current + 1 < positions.count { caret = positions[current + 1] }
        normalizeCaret()
    }

    /// Puts the caret at a tapped index (from MTDisplay.closestIndex(to:)), or the nearest valid one.
    public func moveCaret(to index: MTMathListIndex) {
        var index = index
        if index.innermostType == .nucleus, let parent = index.parent {
            index = parent.next  // between a nucleus and its scripts: after the atom
        }
        caret = index
        normalizeCaret()
    }

    public func moveToEnd() {
        caret = MTMathListIndex(level0Index: mathList.atoms.count)
        normalizeCaret()
    }

    // MARK: - Internals

    private func place(_ atom: MTMathAtom) {
        guard let (list, position) = mathList.list(containing: caret) else { return }
        // A relation typed in a denominator goes after the fraction (½ = …).
        if atom.type == .relation, caret.innermostType == .denominator, let parent = caret.parent {
            caret = parent.next
            place(atom)
            return
        }
        if position < list.atoms.count, Self.isEmptySlot(list.atoms[position]) {
            let slot = list.atoms[position]
            if atom.isScriptAllowed() {
                atom.superScript = slot.superScript
                atom.subScript = slot.subScript
            }
            list.removeAtom(at: position)
        }
        list.insert(atom, at: position)
        caret = caret.replacingInnermost(with: position + 1)
    }

    private func exponentOrSubscript(_ type: MTMathListIndex.MTMathListSubIndexType) {
        if caret.contains(type) {
            // Pressed again inside it: out, after the atom.
            var index = caret
            while index.contains(type), let parent = index.parent { index = parent }
            caret = index.next
            return
        }
        guard let (list, position) = mathList.list(containing: caret) else { return }
        var base: MTMathAtom
        var baseIndex: MTMathListIndex
        if position > 0, list.atoms[position - 1].isScriptAllowed() {
            base = list.atoms[position - 1]
            baseIndex = caret.replacingInnermost(with: position - 1)
        } else {
            // Nothing to put it on: an empty slot carries it.
            base = MTMathAtomFactory.placeholder()
            if position < list.atoms.count, Self.isEmptySlot(list.atoms[position]) {
                base = list.atoms[position]
            } else {
                list.insert(base, at: position)
            }
            baseIndex = caret.replacingInnermost(with: position)
        }
        if base.subList(type) == nil {
            let script = MTMathList()
            script.add(MTMathAtomFactory.placeholder())
            if type == .superscript { base.superScript = script } else { base.subScript = script }
            caret = baseIndex.into(type, at: 0)
        } else {
            caret = baseIndex.into(type, at: base.subList(type)!.atoms.count)
        }
    }

    /// `/`: the number or letters just before the caret become the numerator (MathEditor).
    private func fraction() {
        guard let (list, position) = mathList.list(containing: caret) else { return }
        let taken = Self.termBefore(position, in: list, numbersAndLettersOnly: true)
        let numerator = MTMathList()
        for atom in list.atoms[taken] { numerator.add(atom) }
        if !taken.isEmpty { list.removeAtoms(in: taken.lowerBound...(taken.upperBound - 1)) }
        if numerator.atoms.isEmpty { numerator.add(MTMathAtomFactory.placeholder()) }
        let denominator = MTMathList()
        denominator.add(MTMathAtomFactory.placeholder())
        let fraction = MTMathAtomFactory.fraction(withNumerator: numerator, denominator: denominator)
        let start = taken.isEmpty ? position : taken.lowerBound
        if start < list.atoms.count, Self.isEmptySlot(list.atoms[start]) { list.removeAtom(at: start) }
        list.insert(fraction, at: start)
        let fractionIndex = caret.replacingInnermost(with: start)
        caret = taken.isEmpty ? fractionIndex.into(.numerator, at: 0) : fractionIndex.into(.denominator, at: 0)
    }

    /// The caret never sits just after an empty slot: it goes onto the slot. Slots are drawn
    /// white, the one at the caret black.
    private func normalizeCaret() {
        let positions = caretPositions
        if !positions.contains(caret) {
            if let previous = caret.previous, positions.contains(previous) {
                caret = previous
            } else if let nearest = positions.last(where: { Self.isInside($0, from: MTMathListIndex(level0Index: 0), to: caret) }) {
                caret = nearest
            } else {
                caret = positions.last ?? MTMathListIndex(level0Index: 0)
            }
        }
        Self.paintSlots(mathList)
        if let atom = mathList.atom(at: caret), atom.type == .placeholder, caret.innermostType != .nucleus {
            atom.nucleus = "\u{25A0}"
        }
    }

    private func fillIfEmpty(_ list: MTMathList) {
        if list !== mathList && list.atoms.isEmpty { list.add(MTMathAtomFactory.placeholder()) }
    }

    // MARK: - Helpers

    static func isEmptySlot(_ atom: MTMathAtom) -> Bool {
        atom.type == .placeholder && atom.superScript == nil && atom.subScript == nil
    }

    static func isEmpty(_ list: MTMathList?) -> Bool {
        list?.atoms.allSatisfy(isEmptySlot) ?? true
    }

    private static func paintSlots(_ list: MTMathList) {
        for atom in list.atoms {
            if atom.type == .placeholder { atom.nucleus = "\u{25A1}" }
            for (_, sub) in atom.editableSubLists { paintSlots(sub) }
        }
    }

    /// Caret places in a list: before each atom (not right after an empty slot: the slot
    /// itself is the place), inside each atom's parts, and at the end.
    private static func positions(in list: MTMathList, wrap: (MTMathListIndex) -> MTMathListIndex) -> [MTMathListIndex] {
        var out: [MTMathListIndex] = []
        for (position, atom) in list.atoms.enumerated() {
            if position == 0 || !isEmptySlot(list.atoms[position - 1]) {
                out.append(wrap(MTMathListIndex(level0Index: position)))
            }
            for (type, sub) in atom.editableSubLists {
                out += positions(in: sub) { inner in wrap(MTMathListIndex(at: position, with: inner, type: type)) }
            }
        }
        if list.atoms.last.map(isEmptySlot) != true {
            out.append(wrap(MTMathListIndex(level0Index: list.atoms.count)))
        }
        return out
    }

    /// The atoms before `position` that form one term: a run of numbers and letters, or a
    /// single structure (fraction, root, bracket…).
    private static func termBefore(_ position: Int, in list: MTMathList, numbersAndLettersOnly: Bool = false) -> Range<Int> {
        var start = position
        while start > 0, [.number, .variable].contains(list.atoms[start - 1].type) { start -= 1 }
        if start == position, !numbersAndLettersOnly, position > 0,
           [.fraction, .radical, .accent, .overline, .inner, .close].contains(list.atoms[position - 1].type) {
            start = position - 1
        }
        return start..<position
    }

    /// True when `index` is at or after `from` and before `to` (same tree).
    private static func isInside(_ index: MTMathListIndex, from: MTMathListIndex, to: MTMathListIndex) -> Bool {
        compare(index, from) >= 0 && compare(index, to) < 0
    }

    /// Orders two indexes in reading order (a position inside an atom comes after the place
    /// before it).
    static func compare(_ a: MTMathListIndex, _ b: MTMathListIndex) -> Int {
        if a.atomIndex != b.atomIndex { return a.atomIndex < b.atomIndex ? -1 : 1 }
        switch (a.subIndex, b.subIndex) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (x?, y?):
            if a.subIndexType != b.subIndexType {
                let order: [MTMathListIndex.MTMathListSubIndexType] =
                    [.nucleus, .numerator, .denominator, .degree, .radicand, .innerList, .superscript, .ssubscript]
                return (order.firstIndex(of: a.subIndexType) ?? 0) < (order.firstIndex(of: b.subIndexType) ?? 0) ? -1 : 1
            }
            return compare(x, y)
        }
    }

    /// A character typed on the keyboard as an atom.
    static func atom(for character: Character) -> MTMathAtom? {
        switch character {
        case "*", "×": return MTMathAtomFactory.times()
        case "÷": return MTMathAtomFactory.divide()
        case "·": return MTMathAtomFactory.atom(forLatexSymbol: "cdot")
        case " ": return nil
        default:
            if let atom = MTMathAtomFactory.atom(forCharacter: character) { return atom }
            // Unicode symbols from the keyboard (≤, π, ∠…): the LaTeX command they stand for.
            if let name = MTMathAtomFactory.textToLatexSymbolName[String(character)],
               let atom = MTMathAtomFactory.atom(forLatexSymbol: name) { return atom }
            return MTMathAtom(type: .ordinary, value: String(character))
        }
    }

    /// LaTeX the editor can work in: `\left(…\right)` brackets become plain ones (whose content
    /// stays editable), and `\dfrac` a `\frac`.
    static func editable(_ latex: String) -> String {
        var out = latex
        for (from, to) in [("\\left(", "("), ("\\right)", ")"), ("\\left[", "["), ("\\right]", "]"),
                           ("\\left\\{", "\\{"), ("\\right\\}", "\\}"), ("\\left|", "|"), ("\\right|", "|"),
                           ("\\left.", ""), ("\\right.", ""), ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }

    /// Tables (`cases`, matrices) and `\left…\right` groups have no caret positions inside.
    private static func containsUneditable(_ list: MTMathList) -> Bool {
        list.atoms.contains { atom in
            atom.type == .table || atom.type == .inner || atom.editableSubLists.contains { containsUneditable($0.1) }
        }
    }

    /// A copy without empty slots, for the LaTeX output.
    private static func withoutSlots(_ list: MTMathList) -> MTMathList {
        let out = MTMathList()
        for atom in list.atoms {
            if isEmptySlot(atom) { continue }
            let copy: MTMathAtom = atom.copy()
            if copy.type == .placeholder { copy.type = .ordinary; copy.nucleus = "" }
            if let sup = copy.superScript { copy.superScript = withoutSlots(sup) }
            if let sub = copy.subScript { copy.subScript = withoutSlots(sub) }
            switch copy {
            case let fraction as MTFraction:
                fraction.numerator = fraction.numerator.map(withoutSlots)
                fraction.denominator = fraction.denominator.map(withoutSlots)
            case let radical as MTRadical:
                radical.radicand = radical.radicand.map(withoutSlots)
                if let degree = radical.degree { radical.degree = isEmpty(degree) ? nil : withoutSlots(degree) }
            case let accent as MTAccent:
                accent.innerList = accent.innerList.map(withoutSlots)
            case let line as MTOverLine:
                line.innerList = line.innerList.map(withoutSlots)
            case let line as MTUnderLine:
                line.innerList = line.innerList.map(withoutSlots)
            default:
                break
            }
            out.add(copy)
        }
        return out
    }
}

extension MTMathListIndex {
    /// The same path with another position in the innermost list.
    func replacingInnermost(with position: Int) -> MTMathListIndex {
        guard subIndexType != .none, let subIndex else { return MTMathListIndex(level0Index: position) }
        if subIndexType == .nucleus { return MTMathListIndex(level0Index: position) }
        return MTMathListIndex(at: atomIndex, with: subIndex.replacingInnermost(with: position), type: subIndexType)
    }
}
