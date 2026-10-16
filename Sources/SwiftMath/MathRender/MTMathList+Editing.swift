//
//  MTMathList+Editing.swift
//
//  Inserting, removing and finding atoms at an MTMathListIndex: a path into nested lists
//  (fractions, radicals, scripts, and the content under accents and lines).
//
//  Ported from MathEditor (https://github.com/kostub/MathEditor), MTMathList+Editing.m:
//  Created by Kostub Deshmukh on 9/5/13.
//  Copyright (C) 2013 MathChat
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import Foundation

extension MTMathAtom {
    /// The list a sub-index of this atom leads into, or nil when the atom has no such part.
    public func subList(_ type: MTMathListIndex.MTMathListSubIndexType) -> MTMathList? {
        switch type {
        case .superscript: return superScript
        case .ssubscript: return subScript
        case .numerator: return (self as? MTFraction)?.numerator
        case .denominator: return (self as? MTFraction)?.denominator
        case .radicand: return (self as? MTRadical)?.radicand
        case .degree: return (self as? MTRadical)?.degree
        case .innerList:
            switch self {
            case let accent as MTAccent: return accent.innerList
            case let line as MTOverLine: return line.innerList
            case let line as MTUnderLine: return line.innerList
            default: return nil
            }
        case .none, .nucleus: return nil
        }
    }

    /// The parts of this atom that can be edited, in reading order (scripts last).
    public var editableSubLists: [(MTMathListIndex.MTMathListSubIndexType, MTMathList)] {
        let order: [MTMathListIndex.MTMathListSubIndexType] =
            [.numerator, .denominator, .degree, .radicand, .innerList, .superscript, .ssubscript]
        return order.compactMap { type in subList(type).map { (type, $0) } }
    }
}

extension MTMathList {

    /// Inserts `atom` before the atom at `index` (which may be inside a sub-list).
    public func insert(_ atom: MTMathAtom, at index: MTMathListIndex) {
        guard index.atomIndex <= atoms.count else { return }
        switch index.subIndexType {
        case .none:
            insert(atom, at: index.atomIndex)
        case .nucleus:
            // Inside the nucleus of an atom with scripts: the new atom takes the scripts over.
            guard index.atomIndex < atoms.count else { return }
            let current = atoms[index.atomIndex]
            guard atom.subScript == nil, atom.superScript == nil, atom.isScriptAllowed() else { return }
            atom.subScript = current.subScript
            atom.superScript = current.superScript
            current.subScript = nil
            current.superScript = nil
            insert(atom, at: index.atomIndex + (index.subIndex?.atomIndex ?? 0))
        default:
            guard index.atomIndex < atoms.count, let sub = index.subIndex,
                  let list = atoms[index.atomIndex].subList(index.subIndexType) else { return }
            list.insert(atom, at: sub)
        }
    }

    /// Removes the atom at `index`.
    public func removeAtom(at index: MTMathListIndex) {
        guard index.atomIndex < atoms.count else { return }
        switch index.subIndexType {
        case .none:
            removeAtom(at: index.atomIndex)
        case .nucleus:
            let current = atoms[index.atomIndex]
            if index.atomIndex > 0, case let previous = atoms[index.atomIndex - 1],
               previous.subScript == nil, previous.superScript == nil, previous.isScriptAllowed() {
                // The previous atom takes the scripts over.
                previous.superScript = current.superScript
                previous.subScript = current.subScript
                removeAtom(at: index.atomIndex)
            } else {
                current.nucleus = ""
            }
        default:
            guard let sub = index.subIndex, let list = atoms[index.atomIndex].subList(index.subIndexType) else { return }
            list.removeAtom(at: sub)
        }
    }

    /// The atom at `index`, or nil.
    public func atom(at index: MTMathListIndex?) -> MTMathAtom? {
        guard let index, index.atomIndex < atoms.count else { return nil }
        let atom = atoms[index.atomIndex]
        switch index.subIndexType {
        case .none, .nucleus:
            return atom
        default:
            return atom.subList(index.subIndexType)?.atom(at: index.subIndex)
        }
    }

    /// The list that `index` points into (the innermost one) and the position in it.
    public func list(containing index: MTMathListIndex) -> (list: MTMathList, position: Int)? {
        switch index.subIndexType {
        case .none:
            return (self, index.atomIndex)
        case .nucleus:
            return (self, index.atomIndex + (index.subIndex?.atomIndex ?? 0))
        default:
            guard index.atomIndex < atoms.count, let sub = index.subIndex,
                  let list = atoms[index.atomIndex].subList(index.subIndexType) else { return nil }
            return list.list(containing: sub)
        }
    }
}

extension MTMathListIndex {
    /// The index one atom further in the same list.
    public var next: MTMathListIndex { nextIndex() }
    /// The index one atom back in the same list, nil at the start of a list.
    public var previous: MTMathListIndex? { prevIndex() }
    /// The index of the atom whose part this index is in (one level out), nil at the top level.
    public var parent: MTMathListIndex? { levelDown() }
    /// The innermost part this index is in (`.none` at the top level).
    public var innermostType: MTMathListSubIndexType { finalSubIndexType() }
    /// True at the first position of a list.
    public var isAtStartOfList: Bool { isBeginningOfLine() }
    /// The same position one level deeper, in part `type` of the atom at this index.
    public func into(_ type: MTMathListSubIndexType, at position: Int) -> MTMathListIndex {
        levelUp(with: MTMathListIndex(level0Index: position), type: type)
    }
    public func contains(_ type: MTMathListSubIndexType) -> Bool { hasSubIndex(ofType: type) }
}
