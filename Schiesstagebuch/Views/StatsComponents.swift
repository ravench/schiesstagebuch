import SwiftUI
import Charts

/// Time window used across all statistics screens.
enum StatsPeriod: Hashable {
    case all
    case year(Int)
    case last12Months

    var title: String {
        switch self {
        case .all: "Gesamt"
        case .year(let y): String(y)
        case .last12Months: "Letzte 12 Monate"
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
                tile("Ø pro Eintrag",
                     entries.isEmpty ? "–" : (entries.totalShots / entries.count).formatted(), "divide")
                tile("Zuletzt",
                     entries.map(\.date).max()?.formatted(.dateTime.day().month().year(.twoDigits)) ?? "–",
                     "calendar")
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
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
                Text(title).font(.headline)
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
