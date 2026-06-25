import SwiftUI

// MARK: - Count Trend Chart
//
// A custom Path-based sparkline showing quantity over time from count history.
// Uses no Charts framework — fully compatible with all iOS 16+ targets.

struct CountTrendChart: View {

    let item: InventoryItem

    // MARK: - Data preparation

    /// Sorted data points: each count + a synthetic "now" point using current qty.
    private struct DataPoint: Identifiable {
        let id: UUID
        let date: Date
        let quantity: Double
    }

    private var dataPoints: [DataPoint] {
        let counts = item.countHistory
            .sorted { $0.countDate < $1.countDate }
            .map { DataPoint(id: $0.id, date: $0.countDate, quantity: $0.countedQuantity) }

        guard !counts.isEmpty else { return [] }

        // Append a synthetic "current" point only if it differs from the last count
        let last = counts.last!
        if last.quantity != item.currentQuantity || Calendar.current.isDateInToday(last.date) == false {
            let now = DataPoint(id: UUID(), date: Date(), quantity: item.currentQuantity)
            return counts + [now]
        }
        return counts
    }

    private var minQty: Double { dataPoints.map(\.quantity).min() ?? 0 }
    private var maxQty: Double { dataPoints.map(\.quantity).max() ?? 1 }
    private var qtyRange: Double { max(maxQty - minQty, 1) }

    // MARK: - Colours

    private var lineColor: Color {
        item.isOutOfStock ? .red : item.isLowStock ? .orange : .green
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (matches DetailSection style)
            Text("Quantity Trend")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 12) {
                if dataPoints.count < 2 {
                    emptyState
                } else {
                    chartBody
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Count at least 2 times to see a trend")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Chart

    private var chartBody: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Y-axis labels + chart area side by side
            HStack(alignment: .top, spacing: 6) {

                // Y-axis labels (max / min)
                VStack(alignment: .trailing) {
                    Text(maxQty.smartFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(minQty.smartFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 36)
                .frame(height: 90)

                // Chart canvas
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack(alignment: .topLeading) {

                        // Horizontal grid lines (3 lines)
                        gridLines(width: w, height: h)

                        // Filled area under curve
                        areaPath(width: w, height: h)
                            .fill(
                                LinearGradient(
                                    colors: [lineColor.opacity(0.25), lineColor.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Line
                        linePath(width: w, height: h)
                            .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Data point dots
                        ForEach(Array(dataPoints.enumerated()), id: \.1.id) { idx, point in
                            let x = xPos(index: idx, width: w)
                            let y = yPos(qty: point.quantity, height: h)
                            Circle()
                                .fill(lineColor)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }

                        // Min threshold marker line (if minQuantity set)
                        if item.minQuantity > 0 && item.minQuantity >= minQty && item.minQuantity <= maxQty {
                            let y = yPos(qty: item.minQuantity, height: h)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }
                .frame(height: 90)
            }

            // X-axis: first and last date
            HStack {
                Text(dataPoints.first!.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(dataPoints.last!.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 42) // align with chart canvas (y-axis width + spacing)

            // Summary row
            summaryRow
        }
    }

    // MARK: - Path helpers

    private func xPos(index: Int, width: CGFloat) -> CGFloat {
        guard dataPoints.count > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(dataPoints.count - 1) * width
    }

    private func yPos(qty: Double, height: CGFloat) -> CGFloat {
        let fraction = (qty - minQty) / qtyRange
        // Invert: higher qty = lower y value (top of canvas)
        return height - CGFloat(fraction) * height
    }

    private func linePath(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        for (idx, point) in dataPoints.enumerated() {
            let pt = CGPoint(x: xPos(index: idx, width: width),
                             y: yPos(qty: point.quantity, height: height))
            if idx == 0 { path.move(to: pt) }
            else         { path.addLine(to: pt) }
        }
        return path
    }

    private func areaPath(width: CGFloat, height: CGFloat) -> Path {
        var path = linePath(width: width, height: height)
        // Close down to bottom-right, then bottom-left
        path.addLine(to: CGPoint(x: xPos(index: dataPoints.count - 1, width: width), y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
            Path { p in
                let y = height - CGFloat(fraction) * height
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(Color(.systemGray5), lineWidth: 0.5)
        }
    }

    // MARK: - Summary row

    private var summaryRow: some View {
        let first = dataPoints.first!.quantity
        let last  = dataPoints.last!.quantity
        let delta = last - first
        let pct   = first > 0 ? (delta / first) * 100 : 0
        let sign  = delta >= 0 ? "+" : ""
        let uom   = item.uom?.symbol ?? ""

        return HStack(spacing: 16) {
            summaryChip(
                label: "Start",
                value: "\(first.smartFormatted) \(uom)",
                color: .secondary
            )
            summaryChip(
                label: "Now",
                value: "\(last.smartFormatted) \(uom)",
                color: lineColor
            )
            summaryChip(
                label: "Change",
                value: "\(sign)\(delta.smartFormatted) (\(sign)\(String(format: "%.0f", pct))%)",
                color: delta == 0 ? .secondary : delta > 0 ? .green : .red
            )
            Spacer()
            Text("\(dataPoints.count - 1) count\(dataPoints.count - 1 == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}
