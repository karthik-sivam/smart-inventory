import SwiftUI

// MARK: - Donut Slice Shape

/// A single wedge of a donut chart.
/// Using this as a view's contentShape gives pixel-perfect tap hit-testing
/// on the actual arc area — no angle math needed at gesture time.
struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusFraction: CGFloat   // 0 = full pie, 0.5 = half-hole donut

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer  = min(rect.width, rect.height) / 2
        let inner  = outer * innerRadiusFraction

        var p = Path()
        // Outer arc (clockwise on screen — SwiftUI flips Y so clockwise:false = CW visually)
        p.addArc(center: center, radius: outer,
                 startAngle: startAngle, endAngle: endAngle, clockwise: false)
        // Inner arc (back counter-clockwise to close the wedge)
        p.addArc(center: center, radius: inner,
                 startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Category Donut Chart

struct CategoryDonutChart: View {

    let items: [InventoryItem]
    var selectedCategory: String? = nil
    var onCategoryTapped: ((String) -> Void)? = nil

    // MARK: Private constants

    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink
    ]
    private static let maxNamed = 6          // top-N shown individually; rest → "Other"
    private static let innerFraction: CGFloat = 0.52
    private static let sliceGap: Double = 2.5  // degrees of visual gap between adjacent slices

    // MARK: Slice model

    private struct SliceData: Identifiable {
        let id: String        // category name, or "__other__"
        let name: String
        let count: Int
        let color: Color
        let startAngle: Angle
        let endAngle: Angle
        let isOther: Bool
    }

    // MARK: Computed slices

    private var slices: [SliceData] {
        guard !items.isEmpty else { return [] }

        let grouped = Dictionary(grouping: items, by: \.category)
        let sorted  = grouped
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        let otherN = sorted.dropFirst(Self.maxNamed).reduce(0) { $0 + $1.count }

        typealias Entry = (name: String, count: Int, isOther: Bool)
        var entries: [Entry] = sorted.prefix(Self.maxNamed).map { ($0.name, $0.count, false) }
        if otherN > 0 { entries.append(("Other", otherN, true)) }

        let total = Double(entries.reduce(0) { $0 + $1.count })
        let gap   = Self.sliceGap
        var result: [SliceData] = []
        var current = -90.0   // 12 o'clock

        for (i, entry) in entries.enumerated() {
            let fraction = Double(entry.count) / total
            let full     = fraction * 360.0
            let sweep    = max(full - gap, 0.5)   // never collapse to nothing
            let color    = entry.isOther ? Color.gray : Self.palette[i % Self.palette.count]

            result.append(SliceData(
                id:         entry.isOther ? "__other__" : entry.name,
                name:       entry.name,
                count:      entry.count,
                color:      color,
                startAngle: .degrees(current + gap / 2),
                endAngle:   .degrees(current + gap / 2 + sweep),
                isOther:    entry.isOther
            ))
            current += full
        }
        return result
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text("No items yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                HStack(alignment: .center, spacing: 20) {
                    donutView
                        .frame(width: 160, height: 160)

                    legendView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)

                Text(selectedCategory == nil ? "Tap a slice or row to filter" : "Tap again to clear filter")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .animation(.easeInOut, value: selectedCategory)
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: Donut wheel

    private var donutView: some View {
        ZStack {
            ForEach(slices) { slice in
                DonutSlice(
                    startAngle:          slice.startAngle,
                    endAngle:            slice.endAngle,
                    innerRadiusFraction: Self.innerFraction
                )
                .fill(sliceOpacity(slice))
                // KEY: explicit contentShape = tap area is the exact arc, not its bounding box
                .contentShape(DonutSlice(
                    startAngle:          slice.startAngle,
                    endAngle:            slice.endAngle,
                    innerRadiusFraction: Self.innerFraction
                ))
                .onTapGesture {
                    guard !slice.isOther, let cb = onCategoryTapped else { return }
                    cb(slice.name)
                }
                .animation(.easeInOut(duration: 0.2), value: selectedCategory)
            }

            // Center label — allowsHitTesting(false) so it doesn't block slice taps
            centerLabel
                .allowsHitTesting(false)
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let selId = selectedCategory,
               let sel = slices.first(where: { $0.id == selId }) {
                Text("\(sel.count)")
                    .font(.title3).fontWeight(.bold)
                Text(sel.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 72)
                    .lineLimit(2)
            } else {
                Text("\(items.count)")
                    .font(.title3).fontWeight(.bold)
                Text("items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedCategory)
    }

    // MARK: Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { legendRow($0) }
        }
    }

    @ViewBuilder
    private func legendRow(_ slice: SliceData) -> some View {
        let isSelected = selectedCategory == slice.id
        let isActive   = selectedCategory == nil || isSelected

        Button {
            guard !slice.isOther, let cb = onCategoryTapped else { return }
            cb(slice.name)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(slice.color.opacity(isActive ? 1.0 : 0.3))
                    .frame(width: 9, height: 9)

                Text(slice.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(slice.count)")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isActive ? .primary : .secondary.opacity(0.7))
                    .frame(minWidth: 18, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? slice.color.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(slice.isOther)
        .animation(.easeInOut(duration: 0.2), value: selectedCategory)
    }

    // MARK: Helpers

    private func sliceOpacity(_ slice: SliceData) -> Color {
        let active = selectedCategory == nil || selectedCategory == slice.id
        return slice.color.opacity(active ? 1.0 : 0.2)
    }
}
