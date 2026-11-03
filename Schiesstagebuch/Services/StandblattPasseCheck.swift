import Foundation

// A Passe is almost always 3, 4, 5, 6 or 10 shots. A strip that decodes to, say, 11 shots in a
// Passe has most likely picked up a row that is not a counted shot (a repeat whose brackets were
// lost, a misread line). When dropping exactly one shot makes the Passe match its printed sum,
// the parser drops it and says so; otherwise the review screen only warns.

extension ScannedPasse {
    static let usualLengths: Set<Int> = [3, 4, 5, 6, 10]

    var hasUsualLength: Bool { Self.usualLengths.contains(shots.count) }
}

extension ScannedStandblatt {
    /// Passen of printed strips whose length is not a usual one, and shots that were dropped. Handwritten sheets are skipped
    /// (practice series there are often 2 shots).
    var passeLengthIssues: [Issue] {
        guard !handwritten else { return [] }
        var result: [Issue] = passes.enumerated().compactMap { i, passe in
            passe.hasUsualLength ? nil : .unusualPasseLength(i + 1, shots: passe.shots.count)
        }
        if !removedShots.isEmpty { result.append(.removedShots(removedShots)) }
        return result
    }

    /// For each Passe with one shot more than a usual length, drops the shot without which the
    /// Passe matches every printed sum it has. The last such shot is dropped, because a stray
    /// row (an unbracketed repeat) is printed at the end of a Passe.
    mutating func dropExtraShots() {
        guard !handwritten else { return }
        for p in passes.indices {
            let passe = passes[p]
            guard !passe.hasUsualLength, ScannedPasse.usualLengths.contains(passe.shots.count - 1) else { continue }
            // A strip with a single Passe may only print the Total.
            let rings = passe.printedRings ?? (passes.count == 1 ? printedRings : nil)
            let hundredths = passe.printedHundredths ?? (passes.count == 1 ? printedHundredths : nil)
            guard rings != nil || hundredths != nil else { continue }

            for i in passe.shots.indices.reversed() {
                var rest = passe.shots
                let removed = rest.remove(at: i)
                let candidate = ScannedPasse(shots: rest)
                let ringsMatch = rings.map { $0 == candidate.sum(.rings) } ?? true
                let hundredthsMatch = hundredths.map { $0 == candidate.sum(.hundredths) } ?? true
                if ringsMatch && hundredthsMatch {
                    passes[p].shots = rest
                    removedShots.append(removed.number)
                    break
                }
            }
        }
    }
}
