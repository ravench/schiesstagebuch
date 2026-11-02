import SwiftUI
import Charts

/// Time window used across all statistics screens.
enum StatsPeriod: Hashable {
    case all
    case year(Int)
    case last12Months

    var title: String {
        switch self {
        case .all: "Gesamt".loc
        case .year(let y): String(y)
        case .last12Months: "Letzte 12 Monate".loc
        }
    }

    func contains(_ date: Date) -> Bool {
        switch self {
        case .all: true
        case .year(let y): Calendar.current.component(.year, from: date) == y
        case .last12Months: date >= Calendar.current.date(byAdding: .month, value: -12, to: .now)!
        }
    }

    static func options(for entries: [Entry]) -> [StatsPeriod] {
        [.all, .last12Months] + Set(entries.map(\.year)).sorted(by: >).map { .year($0) }
    }
}

struct PeriodPicker: View {
    @Binding var period: StatsPeriod
    let entries: [Entry]

    var body: some View {
        Picker("Zeitraum", selection: $period) {
            ForEach(StatsPeriod.options(for: entries), id: \.self) { Text($0.title).tag($0) }
        }
    }
}

struct KPIGrid: View {
    let entries: [Entry]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Schüsse", entries.totalShots.formatted(), "flame")
                tile("Einträge", entries.count.formatted(), "list.bullet")
            }
            GridRow {
                tile("Zuletzt",
                     entries.map(\.date).max()?.formatted(.dateTime.day().month().year(.twoDigits)) ?? "–",
                     "calendar")
                // Only the percentage: an average per entry or per shot mixes different Stiche
                // (shot counts, A10 vs A100), see `RepeatedStich` for where it is shown.
                if let percent = entries.averagePercentage {
                    tile("Ø Prozent", ScoreFormat.percent(percent), "percent")
                }
            }
            if entries.contains(where: { $0.sighterCount != nil }) {
                GridRow {
                    tile("Probeschüsse", entries.compactMap(\.sighterCount).reduce(0, +).formatted(), "scope")
                    tile("Wertungsschüsse", entries.compactMap(\.scoredCount).reduce(0, +).formatted(), "target")
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title.loc, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Percentage, mean and median of one entry; rows only for what can be computed.
struct ScoreSummary: View {
    let score: Score

    var body: some View {
        if let p = score.percentage { LabeledContent("Prozent", value: ScoreFormat.percent(p)) }
        if let m = score.meanPerShot { LabeledContent("Ø pro Schuss", value: ScoreFormat.points(m)) }
        if let m = score.medianPerShot { LabeledContent("Median pro Schuss", value: ScoreFormat.points(m)) }
    }
}

/// Result percentage per entry over time; shown once two entries have one.
struct ResultTrendChart: View {
    let entries: [Entry]

    private struct Point: Identifiable { let id: UUID; let date: Date; let percent: Double }

    private var points: [Point] {
        entries.compactMap { e in e.score.percentage.map { Point(id: e.id, date: e.date, percent: $0) } }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = points
        if data.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resultat in Prozent").font(.headline)
                Chart(data) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("Prozent", p.percent))
                        .symbol(.circle)
                        .interpolationMethod(.monotone)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(ScoreFormat.percent(v)) } }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            }
        }
    }
}

/// Shots over time: monthly bars, optionally the cumulative total as a line.
struct ShotsOverTimeChart: View {
    let entries: [Entry]
    @State private var cumulative = false

    private struct Point: Identifiable { let month: Date; let shots: Int; var id: Date { month } }

    private var monthly: [Point] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { cal.date(from: cal.dateComponents([.year, .month], from: $0.date))! }
        return grouped.map { Point(month: $0, shots: $1.totalShots) }.sorted { $0.month < $1.month }
    }

    private var running: [Point] {
        var total = 0
        return monthly.map { total += $0.shots; return Point(month: $0.month, shots: total) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schüsse über Zeit").font(.headline)
                Spacer()
                Picker("Darstellung", selection: $cumulative) {
                    Text("Monat").tag(false)
                    Text("Kumuliert").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if monthly.isEmpty {
                Text("Keine Daten").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(cumulative ? running : monthly) { p in
                    if cumulative {
                        AreaMark(x: .value("Monat", p.month, unit: .month), y: .value("Schüsse", p.shots))
                            .foregroundStyle(.tint.opacity(0.15))
                        LineMark(x: .value("Monat", p.month, unit: .month), y: .value("Schüsse", p.shots))
                            .symbol(.circle)
                    } else {
                        BarMark(x: .value("Monat", p.month, unit: .month), y: .value("Schüsse", p.shots))
                            .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
                .frame(height: 200)
            }
        }
    }
}

/// Horizontal bars of shots per group (weapon, range, ammunition …).
struct BreakdownChart<Key: Hashable>: View {
    let title: String
    let entries: [Entry]
    let key: (Entry) -> Key?
    let label: (Key) -> String

    private struct Row: Identifiable { let key: Key; let name: String; let shots: Int; var id: Key { key } }

    private var rows: [Row] {
        Dictionary(grouping: entries.compactMap { e in key(e).map { ($0, e) } }, by: { $0.0 })
            .map { Row(key: $0, name: label($0), shots: $1.map(\.1).totalShots) }
            .sorted { $0.shots > $1.shots }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.loc).font(.headline)
                Chart(rows) { row in
                    BarMark(x: .value("Schüsse", row.shots), y: .value(title, row.name))
                        .foregroundStyle(by: .value(title, row.name))
                        .annotation(position: .trailing) {
                            Text(row.shots.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .frame(height: CGFloat(rows.count) * 34 + 10)
            }
        }
    }
}
