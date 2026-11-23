import Charts
import SwiftUI

/// Time locked today and over the last 7 days.
struct StatsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let days = state.lockedLastSevenDays(now: context.date)
                let week = days.reduce(0) { $0 + $1.seconds }
                List {
                    Section {
                        HStack(spacing: 12) {
                            StatTile(label: "Today", value: DurationText.short(state.lockedToday(now: context.date)))
                            StatTile(label: "Last 7 days", value: DurationText.short(week))
                            StatTile(label: "Daily average", value: DurationText.short(week / 7))
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }

                    // Under an hour on the busiest day, chart minutes so the
                    // axis does not read "0h, 0h, 0h".
                    let peak = days.map(\.seconds).max() ?? 0
                    let inHours = peak >= 3600
                    let unit: Double = inHours ? 3600 : 60
                    let suffix = inHours ? "h" : "m"
                    Section("Last 7 days") {
                        Chart(days, id: \.day) { item in
                            BarMark(
                                x: .value("Day", item.day, unit: .day),
                                y: .value(inHours ? "Hours" : "Minutes", item.seconds / unit)
                            )
                            .foregroundStyle(Color.orange)
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text("\(amount, specifier: "%.0f")\(suffix)")
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...max(inHours ? 1 : 10, peak / unit))
                        .accessibilityValue(days.map { DurationText.short($0.seconds) }.joined(separator: ", "))
                        .frame(height: 180)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Hours locked per day")
                    }
                }
            }
            .navigationTitle("Time locked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
