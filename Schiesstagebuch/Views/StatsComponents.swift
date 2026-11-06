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

    /// The entries in this period, newest first: all of them, the statistics screens list every one.
    func entries(_ entries: [Entry]) -> [Entry] {
        entries.filter { contains($0.date) }.sorted { $0.date > $1.date }
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
                    tile("Probeschüsse", entries.sighterShots.formatted(), "scope")
                    tile("Wertungsschüsse", entries.scoredShots.formatted(), "target")
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

/// Result percentage per entry over time; shown once two entries have one. Entries shot in
/// different positions get a line each, since liegend scores clearly higher than stehend.
struct ResultTrendChart: View {
    let entries: [Entry]

    private struct Point: Identifiable { let id: UUID; let date: Date; let percent: Double; let position: ShootingPosition? }

    private var points: [Point] {
        entries.compactMap { e in
            e.score.percentage.map { Point(id: e.id, date: e.date, percent: $0, position: e.statsPosition) }
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = points
        if data.count >= 2 {
            let positions = Set(data.map(\.position)).sorted { ShootingPosition.order($0) < ShootingPosition.order($1) }
            let split = positions.count > 1
            VStack(alignment: .leading, spacing: 8) {
                Text("Resultat in Prozent").font(.headline)
                Chart(data) { p in
                    if split {
                        LineMark(x: .value("Datum", p.date), y: .value("Prozent", p.percent))
                            .foregroundStyle(by: .value("Stellung", p.position?.title ?? "Ohne Stellung".loc))
                            .symbol(.circle)
                            .interpolationMethod(.monotone)
                    } else {
                        LineMark(x: .value("Datum", p.date), y: .value("Prozent", p.percent))
                            .symbol(.circle)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(ScoreFormat.percent(v)) } }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                // The same colour per position as in the box plots.
                .chartForegroundStyleScale(domain: positions.map { $0?.title ?? "Ohne Stellung".loc }, range: positions.map(ShootingPosition.color))
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

    /// Months between axis labels, so that about six labels show however long the span is.
    static func monthStride(first: Date, last: Date, labels: Int = 6) -> Int {
        let months = (Calendar.current.dateComponents([.month], from: first, to: last).month ?? 0) + 1
        return max(1, Int((Double(months) / Double(labels)).rounded(.up)))
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
                    // Whole months only: automatic ticks fall on weeks for short spans and repeat the month label.
                    AxisMarks(values: .stride(by: .month, count: Self.monthStride(first: monthly.first!.month, last: monthly.last!.month))) {
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

/// Result percentages as box plots, one row per group: box = Q1–Q3, bar = median, whiskers to
/// 1.5 × IQR, every single result as a dot (outliers red); above each row its name, median and n.
/// A row can hold several boxes, one per band (e.g. one per shooting position), each in its colour.
struct BoxPlot: View {
    struct Box {
        /// The band of the row it is drawn in, counted from the top.
        var band = 0
        /// nil: the tint.
        var color: Color?
        /// What VoiceOver reads after the row's name, e.g. the position.
        var name: String?
        /// Percentages (0...1).
        var values: [Double]
        var stats: BoxStats
    }

    struct Row {
        var label: String
        var boxes: [Box]
    }

    let rows: [Row]
    /// Bands per row.
    var bands = 1
    let domain: ClosedRange<Double>

    private struct Dot: Identifiable { let id: Int; let y: Double; let value: Double; let outlier: Bool }

    /// A scale that fits all values, so several plots line up: whole 5 % steps, within 0–100 %.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        let low = max(0, ((values.min() ?? 0) * 20).rounded(.down) / 20)
        let high = min(1, ((values.max() ?? 1) * 20).rounded(.up) / 20)
        return low < high ? low...high : max(0, high - 0.05)...max(high, 0.05)
    }

    // Vertical layout in points, from the top of each row: gap, name, bands, gap.
    private static let top = 20.0, bottom = 10.0
    private var band: Double { bands > 1 ? 14 : 22 }
    private var rowHeight: Double { Self.top + Double(bands) * band + Self.bottom }
    private var height: Double { Double(rows.count) * rowHeight }
    /// The y value (counted upwards, as the chart does) of a band's middle.
    private func y(row: Int, band b: Int) -> Double { height - (Double(row) * rowHeight + Self.top + (Double(b) + 0.5) * band) }

    private var dots: [Dot] {
        var dots: [Dot] = []
        for (i, row) in rows.enumerated() {
            for box in row.boxes {
                for v in box.values {
                    dots.append(Dot(id: dots.count, y: y(row: i, band: box.band), value: v, outlier: box.stats.outliers.contains(v)))
                }
            }
        }
        return dots
    }

    var body: some View {
        Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                ForEach(Array(row.boxes.enumerated()), id: \.offset) { _, box in
                    let s = box.stats
                    let mid = y(row: i, band: box.band)
                    let style = box.color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint)
                    RuleMark(xStart: .value("Prozent", s.lowerWhisker), xEnd: .value("Prozent", s.upperWhisker), y: .value("Zeile", mid))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    RectangleMark(xStart: .value("Q1", s.q1), xEnd: .value("Q3", s.q3), y: .value("Zeile", mid), height: .fixed(band - 4))
                        .foregroundStyle(style.opacity(0.3))
                        .accessibilityHidden(true)
                    RectangleMark(x: .value("Median", s.median), y: .value("Zeile", mid), width: 3, height: .fixed(band))
                        .foregroundStyle(style)
                        .accessibilityLabel(Text(verbatim: [row.label, box.name].compactMap { $0 }.joined(separator: ", ")))
                        .accessibilityValue(Text(verbatim: "\(ScoreFormat.percent(s.median)), n = \(s.count)"))
                }
                // The row's name sits above its bands instead of on the y axis, whose width would
                // differ per plot and shift it against the others.
                RectangleMark(xStart: .value("Prozent", domain.lowerBound), xEnd: .value("Prozent", domain.upperBound),
                              yStart: .value("Zeile", y(row: i, band: 0) + band / 2), yEnd: .value("Zeile", y(row: i, band: bands - 1) - band / 2))
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
                    .annotation(position: .top, alignment: .leading, spacing: 2) { label(row) }
            }
            ForEach(dots) { d in
                PointMark(x: .value("Prozent", d.value), y: .value("Zeile", d.y))
                    .symbolSize(d.outlier ? 30 : 14)
                    .foregroundStyle(d.outlier ? AnyShapeStyle(.red) : AnyShapeStyle(.primary.opacity(0.45)))
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...height)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(ScoreFormat.percent(v)) } }
            }
        }
        .frame(height: height + 30)
    }

    /// The row's name with each box's median and n; with several bands, a dot in the box's colour
    /// tells which band the numbers belong to.
    private func label(_ row: Row) -> some View {
        HStack(spacing: 0) {
            Text(row.label).bold()
            ForEach(Array(row.boxes.enumerated()), id: \.offset) { _, box in
                if bands > 1, let color = box.color {
                    Text(verbatim: "  ● ").foregroundStyle(color)
                } else {
                    Text(verbatim: " · ").foregroundStyle(.secondary)
                }
                Text(verbatim: "\(ScoreFormat.percent(box.stats.median)) · n = \(box.stats.count)").foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospacedDigit())
        .lineLimit(1)
    }
}

extension ShootingPosition {
    /// The same colour for a position in every statistics chart; grey for none.
    static func color(_ position: ShootingPosition?) -> Color {
        switch position {
        case .prone?: .blue
        case .rested?: .teal
        case .kneeling?: .orange
        case .standing?: .purple
        case nil: .gray
        }
    }
}

/// Which colour stands for which shooting position.
struct PositionLegend: View {
    let positions: [ShootingPosition?]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, position in
                HStack(spacing: 4) {
                    Circle().fill(ShootingPosition.color(position)).frame(width: 8, height: 8)
                    Text(position?.title ?? "Ohne Stellung".loc)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Box plots of result percentages per ammunition lot, so lots can be compared however each entry
/// was scored (points of a maximum or a result in percent). One plot per firearm, never pooled: a
/// lot can shoot well in one firearm and badly in another. Within a lot's row, each shooting
/// position gets its own box in its colour, since liegend or aufgelegt scores clearly higher than
/// kniend or stehend.
struct LotResultsChart: View {
    @Environment(\.term) private var term
    let entries: [Entry]

    /// Something to compare: two lots, or one lot in two firearms. One lot in two positions is
    /// what «Resultat pro Stellung» shows.
    static func shows(_ entries: [Entry]) -> Bool {
        entries.lotComparisons.reduce(0) { $0 + $1.lots.count } >= 2
    }

    var body: some View {
        let groups = entries.lotComparisons
        if groups.reduce(0, { $0 + $1.lots.count }) >= 2 {
            let results = groups.flatMap { $0.positions.flatMap(\.lots) }
            let domain = BoxPlot.domain(results.flatMap(\.values))
            let positions = Set(groups.flatMap { $0.positions.map(\.position) }).sorted { ShootingPosition.order($0) < ShootingPosition.order($1) }
            let colored = positions.count > 1
            // A firearm's own page needs no name above the plot.
            let named = Set(groups.map { $0.weapon?.persistentModelID }).count > 1
            VStack(alignment: .leading, spacing: 8) {
                Text("Resultat pro Los").font(.headline)
                if colored { PositionLegend(positions: positions) }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if named {
                        Text(group.weapon?.name ?? term("Ohne Waffe").loc).font(.subheadline.weight(.semibold))
                    }
                    BoxPlot(rows: group.lots.map { lot in
                                BoxPlot.Row(label: group.label(lot), boxes: group.results(lot).map {
                                    BoxPlot.Box(band: $0.band, color: colored ? ShootingPosition.color($0.position) : nil,
                                                name: $0.position?.title, values: $0.result.values, stats: $0.result.stats)
                                })
                            },
                            bands: group.positions.count, domain: domain)
                }
                Text("Box: mittlere Hälfte der Resultate (1. bis 3. Quartil), Strich: Median, Linie: bis 1,5 × Quartilsabstand, Punkte: einzelne Resultate, rot: Ausreisser. Zählt Einträge mit Prozent (Punkte mit Maximum oder Resultat in %).")
                    .font(.caption).foregroundStyle(.secondary)
                if named {
                    Text(term("Getrennt pro Waffe: Dasselbe Los kann in einer anderen Waffe anders schiessen.").loc)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if results.contains(where: { $0.count < BoxStats.reliableCount }) {
                    Text("Mit weniger als 5 Resultaten pro Los sind Quartile wenig aussagekräftig.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Box plots of result percentages per shooting position, one per firearm shot in two positions or
/// more: liegend or aufgelegt usually scores clearly higher than kniend or stehend, so a single
/// average over all positions says little, and across firearms it would compare rifles with pistols.
struct PositionResultsChart: View {
    @Environment(\.term) private var term
    let entries: [Entry]

    static func shows(_ entries: [Entry]) -> Bool { !entries.positionComparisons.isEmpty }

    var body: some View {
        let groups = entries.positionComparisons
        if !groups.isEmpty {
            let domain = BoxPlot.domain(groups.flatMap { $0.positions.flatMap(\.values) })
            // A firearm's own page needs no name above the plot.
            let named = Set(entries.map { $0.weapon?.persistentModelID }).count > 1
            VStack(alignment: .leading, spacing: 8) {
                Text("Resultat pro Stellung").font(.headline)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if named {
                        Text(group.weapon?.name ?? term("Ohne Waffe").loc).font(.subheadline.weight(.semibold))
                    }
                    BoxPlot(rows: group.positions.map {
                                BoxPlot.Row(label: $0.position?.title ?? "Ohne Stellung".loc,
                                            boxes: [BoxPlot.Box(color: ShootingPosition.color($0.position), values: $0.values, stats: $0.stats)])
                            },
                            domain: domain)
                }
                Text("Box: mittlere Hälfte der Resultate (1. bis 3. Quartil), Strich: Median, Linie: bis 1,5 × Quartilsabstand, Punkte: einzelne Resultate, rot: Ausreisser. Zählt Einträge mit Prozent (Punkte mit Maximum oder Resultat in %).")
                    .font(.caption).foregroundStyle(.secondary)
                if groups.contains(where: { $0.positions.contains { $0.stats.count < BoxStats.reliableCount } }) {
                    Text("Mit weniger als 5 Resultaten pro Stellung sind Quartile wenig aussagekräftig.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
