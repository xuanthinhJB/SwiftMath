//
//  MTDisplay+Editing.swift
//
//  Hit-testing and caret positions for a math editor: which index of the math list a point
//  falls on, and where the caret for an index is drawn.
//
//  Ported from MathEditor (https://github.com/kostub/MathEditor), MTDisplay+Editing.m:
//  Created by Kostub Deshmukh on 9/6/13.
//  Copyright (C) 2013 MathChat
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import CoreText
import Foundation

/// How far outside a display's bounds a point still counts as inside it.
private let kPixelDelta: CGFloat = 2

/// Manhattan distance from a point to the nearest edge of a rectangle (0 inside it).
private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    var distance: CGFloat = 0
    if point.x < rect.minX {
        distance += rect.minX - point.x
    } else if point.x > rect.maxX {
        distance += point.x - rect.maxX
    }
    if point.y < rect.minY {
        distance += rect.minY - point.y
    } else if point.y > rect.maxY {
        distance += point.y - rect.maxY
    }
    return distance
}

extension MTDisplay {

    /// The index in the math list before which a character typed at `point` goes, or nil.
    /// `point` is in the display's coordinates: x to the right and y up from the baseline,
    /// with the display at its `position`.
    public func closestIndex(to point: CGPoint) -> MTMathListIndex? {
        switch self {
        case let list as MTMathListDisplay: return list.listClosestIndex(to: point)
        case let line as MTCTLineDisplay: return line.lineClosestIndex(to: point)
        case let fraction as MTFractionDisplay: return fraction.fractionClosestIndex(to: point)
        case let radical as MTRadicalDisplay: return radical.radicalClosestIndex(to: point)
        default: return nil
        }
    }

    /// Where the caret for `index` is drawn (on the baseline), in the same coordinates as
    /// `closestIndex(to:)`; nil when the index is not in this display.
    public func caretPosition(for index: MTMathListIndex?) -> CGPoint? {
        guard let index else { return nil }
        switch self {
        case let list as MTMathListDisplay: return list.listCaretPosition(for: index)
        case let line as MTCTLineDisplay: return line.lineCaretPosition(for: index)
        case is MTFractionDisplay, is MTRadicalDisplay:
            // The caret goes before the fraction or radical.
            return index.subIndexType == .none ? position : nil
        default: return nil
        }
    }
}

// MARK: - A line of text (CTLine)

extension MTCTLineDisplay {

    fileprivate func lineClosestIndex(to point: CGPoint) -> MTMathListIndex? {
        let relative = CGPoint(x: point.x - position.x, y: point.y - position.y)
        let stringIndex = CTLineGetStringIndexForPosition(line, relative)
        if stringIndex == kCFNotFound { return nil }
        return MTMathListIndex(level0Index: range.location + mathListIndex(forStringIndex: stringIndex))
    }

    fileprivate func lineCaretPosition(for index: MTMathListIndex) -> CGPoint? {
        guard index.subIndexType == .none else { return nil }
        // Measured on the CTLine, not `width`: a nucleus display is as wide as its scripts.
        guard index.atomIndex >= range.location, index.atomIndex <= NSMaxRange(range) else { return nil }
        let stringIndex = self.stringIndex(forMathListIndex: index.atomIndex - range.location)
        let offset = CTLineGetOffsetForStringIndex(line, stringIndex, nil)
        return CGPoint(x: position.x + offset, y: position.y)
    }

    /// An atom can be several characters (e.g. "sin"), so string and atom indexes differ.
    /// CoreText works in UTF-16, hence `utf16.count`.
    private func mathListIndex(forStringIndex stringIndex: Int) -> Int {
        var covered = 0
        for (atomIndex, atom) in atoms.enumerated() {
            if covered >= stringIndex { return atomIndex }
            covered += atom.nucleus.utf16.count
        }
        return atoms.count
    }

    private func stringIndex(forMathListIndex atomIndex: Int) -> Int {
        atoms.prefix(atomIndex).reduce(0) { $0 + $1.nucleus.utf16.count }
    }
}

// MARK: - Fractions and radicals

extension MTFractionDisplay {

    fileprivate func fractionClosestIndex(to point: CGPoint) -> MTMathListIndex? {
        if point.x < position.x - kPixelDelta {
            return MTMathListIndex(level0Index: range.location)  // before the fraction
        }
        if point.x > position.x + width + kPixelDelta {
            return MTMathListIndex(level0Index: NSMaxRange(range))  // after it
        }
        guard let numerator, let denominator else { return nil }
        if distance(from: point, to: numerator.displayBounds()) < distance(from: point, to: denominator.displayBounds()) {
            return MTMathListIndex(at: range.location, with: numerator.closestIndex(to: point), type: .numerator)
        }
        return MTMathListIndex(at: range.location, with: denominator.closestIndex(to: point), type: .denominator)
    }

    fileprivate func subDisplay(for type: MTMathListIndex.MTMathListSubIndexType) -> MTMathListDisplay? {
        switch type {
        case .numerator: return numerator
        case .denominator: return denominator
        default: return nil
        }
    }
}

extension MTRadicalDisplay {

    fileprivate func radicalClosestIndex(to point: CGPoint) -> MTMathListIndex? {
        if point.x < position.x - kPixelDelta {
            return MTMathListIndex(level0Index: range.location)
        }
        if point.x > position.x + width + kPixelDelta {
            return MTMathListIndex(level0Index: NSMaxRange(range))
        }
        guard let radicand else { return nil }
        if let degree,
           distance(from: point, to: degree.displayBounds()) < distance(from: point, to: radicand.displayBounds()) {
            return MTMathListIndex(at: range.location, with: degree.closestIndex(to: point), type: .degree)
        }
        return MTMathListIndex(at: range.location, with: radicand.closestIndex(to: point), type: .radicand)
    }

    fileprivate func subDisplay(for type: MTMathListIndex.MTMathListSubIndexType) -> MTMathListDisplay? {
        switch type {
        case .radicand: return radicand
        case .degree: return degree
        default: return nil
        }
    }
}

// MARK: - A list of displays

extension MTMathListDisplay {

    fileprivate func listClosestIndex(to point: CGPoint) -> MTMathListIndex? {
        // Sub-displays are positioned relative to this display.
        let point = CGPoint(x: point.x - position.x, y: point.y - position.y)
        var closest: MTDisplay?
        var minDistance = CGFloat.greatestFiniteMagnitude
        var underPoint: [MTDisplay] = []  // displays whose x-range holds the point
        for display in subDisplays {
            let bounds = display.displayBounds()
            if bounds.minX - kPixelDelta <= point.x && point.x <= bounds.maxX + kPixelDelta {
                underPoint.append(display)
            }
            let d = distance(from: point, to: bounds)
            // SwiftMath sizes a nucleus with a script to include the script, so the two overlap:
            // on a tie the (smaller, inner) script wins.
            let isScript = (display as? MTMathListDisplay).map { $0.type != .regular } ?? false
            if d < minDistance || (d == minDistance && isScript) {
                closest = display
                minDistance = d
            }
        }

        let hit: MTDisplay?
        if underPoint.isEmpty {
            if point.x <= -kPixelDelta { return MTMathListIndex(level0Index: range.location) }
            if point.x >= width + kPixelDelta { return MTMathListIndex(level0Index: NSMaxRange(range)) }
            hit = closest  // inside the list but between displays
        } else if underPoint.count == 1 {
            hit = underPoint[0]
            // Near the end and below the display: the caret goes at the end of the list.
            if point.x >= width - kPixelDelta, let hit, point.y <= hit.displayBounds().minY - kPixelDelta {
                return MTMathListIndex(level0Index: NSMaxRange(range))
            }
        } else {
            hit = closest  // overlapping displays (a nucleus and its script): the nearest wins
        }
        guard let hit, let index = hit.closestIndex(to: point) else { return nil }

        if let script = hit as? MTMathListDisplay, script.type != .regular {
            // A subscript or superscript of the atom at `script.index`.
            let type: MTMathListIndex.MTMathListSubIndexType = script.type == .ssubscript ? .ssubscript : .superscript
            return MTMathListIndex(at: script.index, with: index, type: type)
        }
        if hit.hasScript && index.atomIndex == NSMaxRange(hit.range) {
            // At the end of an atom with a script: before the script, not after it.
            return MTMathListIndex(at: index.atomIndex - 1, with: MTMathListIndex(level0Index: 1), type: .nucleus)
        }
        return index
    }

    /// The display that holds `index` (not recursing into it).
    private func subDisplay(for index: MTMathListIndex) -> MTDisplay? {
        if index.subIndexType == .superscript || index.subIndexType == .ssubscript {
            return subDisplays.first { display in
                guard let script = display as? MTMathListDisplay, script.index == index.atomIndex else { return false }
                return (script.type == .ssubscript && index.subIndexType == .ssubscript)
                    || (script.type == .superscript && index.subIndexType == .superscript)
            }
        }
        guard let display = subDisplays.first(where: {
            !($0 is MTMathListDisplay) && NSLocationInRange(index.atomIndex, $0.range)
        }) else { return nil }
        switch index.subIndexType {
        case .none, .nucleus: return display
        case .numerator, .denominator: return (display as? MTFractionDisplay)?.subDisplay(for: index.subIndexType)
        case .radicand, .degree: return (display as? MTRadicalDisplay)?.subDisplay(for: index.subIndexType)
        case .superscript, .ssubscript: return nil
        }
    }

    fileprivate func listCaretPosition(for index: MTMathListIndex) -> CGPoint? {
        var caret: CGPoint?
        if index.atomIndex == NSMaxRange(range) {
            caret = CGPoint(x: width, y: 0)
        } else if NSLocationInRange(index.atomIndex, range), let display = subDisplay(for: index) {
            switch index.subIndexType {
            case .nucleus:
                let inNucleus = index.atomIndex + (index.subIndex?.atomIndex ?? 0)
                caret = display.caretPosition(for: MTMathListIndex(level0Index: inNucleus))
            case .none:
                caret = display.caretPosition(for: index)
            default:
                caret = display.caretPosition(for: index.subIndex)
            }
        }
        guard let caret else { return nil }
        return CGPoint(x: caret.x + position.x, y: caret.y + position.y)
    }
}
