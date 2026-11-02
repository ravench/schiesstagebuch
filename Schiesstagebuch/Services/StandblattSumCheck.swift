import Foundation

// Every Passe read from a photo is checked against the sums printed on the Standblatt. When the
// read shots don't add up to the printed Subtota/Total, or nothing printed could be read to compare
// with, the scan screen asks before handing the values to the editor, and the entry's notes say so,
// so a misread strip is never saved silently.

extension ScannedStandblatt.Issue {
    /// A printed sum (a Passe's Subtota or the Total) differs from the read shots.
    var isSumMismatch: Bool {
        switch self {
        case .passeMismatch, .totalMismatch: true
        default: false
        }
    }
}

extension ScannedStandblatt {
    enum SumCheck: Equatable {
        /// Every printed sum equals the sum of the read shots.
        case matches
        /// These printed sums differ from the read shots.
        case mismatch([Issue])
        /// No printed Total was read and not every Passe has a printed Subtota, so the shots could not be checked.
        case unchecked
    }

    func sumCheck(_ scoring: StandblattScoring) -> SumCheck {
        let mismatches = issues(scoring).filter(\.isSumMismatch)
        if !mismatches.isEmpty { return .mismatch(mismatches) }
        let everyPasseChecked = !passes.isEmpty && passes.allSatisfy { $0.printed(scoring) != nil }
        return printedTotal(scoring) != nil || everyPasseChecked ? .matches : .unchecked
    }

    /// A line for the entry's notes when the read shots are not confirmed by the printed sums.
    func sumWarning(_ scoring: StandblattScoring) -> String? {
        switch sumCheck(scoring) {
        case .matches:
            return nil
        case let .mismatch(issues):
            let joined = issues.map(\.message).joined(separator: "; ")
            return String(localized: "Summe prüfen: \(joined)")
        case .unchecked:
            let read = sum(scoring)
            return String(localized: "Summe nicht geprüft, kein gedrucktes Total gelesen (Schüsse ergeben \(read.formatted()))")
        }
    }
}
