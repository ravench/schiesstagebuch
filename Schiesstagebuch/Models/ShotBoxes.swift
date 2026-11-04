import Foundation

/// One Passe edited as a row of boxes, one shot per box, numbered 1, 2, 3 … in the editor.
/// There is always one empty box at the end to type the next shot into; the editor shows it only
/// while the Passe is being edited (see `visibleCount(editing:)`). Stored as before:
/// `text` is the Passe's line in `Entry.shotValuesText` ("10 9 10 8,5").
struct ShotBoxes: Equatable {
    private(set) var values: [String]

    init(text: String) {
        values = Self.tokens(text) + [""]
    }

    /// The shots as one line, empty boxes left out.
    var text: String { values.filter { !$0.isEmpty }.joined(separator: " ") }

    /// Shots the user typed into a box, split where `Score.parseShots` splits.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: isSeparator).map(String.init)
    }

    static func isSeparator(_ c: Character) -> Bool { c.isWhitespace || c == ";" || c == "+" }

    /// Puts what was typed into box `index`. A separator (space, ";", "+") ends the shot:
    /// "10 9" fills this box and the next one. Returns the box to move the cursor to,
    /// or nil to stay in this box.
    @discardableResult
    mutating func set(_ input: String, at index: Int) -> Int? {
        guard values.indices.contains(index) else { return nil }
        let parts = Self.tokens(input)
        let endsShot = input.last.map(Self.isSeparator) ?? false
        guard parts.count > 1 || endsShot else {
            values[index] = input
            keepTrailingBox()
            return nil
        }
        values.replaceSubrange(index...index, with: parts.isEmpty ? [""] : parts)
        keepTrailingBox()
        let last = index + max(parts.count, 1) - 1
        return endsShot && !parts.isEmpty ? last + 1 : last
    }

    /// How many boxes the editor shows. The empty box at the end is for typing the next shot, so it only
    /// shows while the Passe is being edited, or when the Passe has no shots yet (there must be a box to tap).
    func visibleCount(editing: Bool) -> Int {
        guard !editing, values.count > 1, values.last?.isEmpty == true else { return values.count }
        return values.count - 1
    }

    /// Drops boxes the user emptied, keeping the empty box at the end. Used when the cursor leaves the Passe.
    mutating func removeEmptyBoxes() {
        values = values.filter { !$0.isEmpty } + [""]
    }

    private mutating func keepTrailingBox() {
        if values.last?.isEmpty != true { values.append("") }
    }
}
