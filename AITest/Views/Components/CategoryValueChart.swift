import SwiftUI

// MARK: - Category Value Chart
//
// Horizontal bar chart showing total inventory value (qty × unitCost)
// broken down by category. Only categories with value > 0 are shown.
// Tapping a bar opens CategoryExplorerView filtered to that category.

struct CategoryValueChart: View {

    let items: [InventoryItem]

    @State private var selectedCategory: String? = nil

    // MARK: - Data

    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink
    ]
    private static let maxBars = 6

    private struct CategoryValue: Identifiable {
        let id: String
        let name: String
        let value: Double
        let itemCount: Int
        let color: Color
    }

    private var categories: [CategoryValue] {
        let grouped = Dictionary(grouping: items, by: \.category)
        let sorted = grouped
            .map { (name: $0.key, value: $0.value.reduce(0) { $0 + $1.totalValue }, count: $0.value.count) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }

        var result: [CategoryValue] = []
        for (idx, entry) in sorted.prefix(Self.maxBars).enumerated() {
            result.append(CategoryValue(
                id:        entry.name,
                name:      entry.name,
                value:     entry.value,
                itemCount: entry.count,
                color:     Self.palette[idx % Self.palette.count]
            ))
        }

        // Remaining categories → "Other"
        let otherValue = sorted.dropFirst(Self.maxBars).reduce(0) { $0 + $1.value }
        let otherCount = sorted.dropFirst(Self.maxBars).reduce(0) { $0 + $1.count }
        if otherValue > 0 {
            result.append(CategoryValue(id: "__other__", name: "Other",
                                        value: otherValue, itemCount: otherCount, color: .gray))
        }
        return result
    }

    private var maxValue: Double { categories.map(\.value).max() ?? 1 }

    private var totalValue: Double { categories.reduce(0) { $0 + $1.value } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Value by Category")
                        .font(.headline).fontWeight(.semibold)
                    Text("Based on unit cost × quantity")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(totalValue))
                        .font(.subheadline).fontWeight(.bold)
                    Text("total")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            if categories.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.secondary)
                    Text("Add unit costs to items to see value breakdown")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(categories) { cat in
                        valueRow(cat)
                    }
                }
                .padding(.horizontal, 4)

                // Selection hint
                Text(selectedCategory == nil
                     ? "Tap a row to highlight"
                     : "Tap again to clear")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .animation(.easeInOut, value: selectedCategory)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Row

    @ViewBuilder
    private func valueRow(_ cat: CategoryValue) -> some View {
        let isSelected = selectedCategory == cat.id
        let isActive   = selectedCategory == nil || isSelected
        let isOther    = cat.id == "__other__"

        Button {
            guard !isOther else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedCategory = isSelected ? nil : cat.id
            }
        } label: {
            HStack(spacing: 10) {
                // Colour dot
                Circle()
                    .fill(cat.color.opacity(isActive ? 1.0 : 0.3))
                    .frame(width: 8, height: 8)

                // Category name
                Text(cat.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(minWidth: 80, maxWidth: 100, alignment: .leading)

                // Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(cat.color.opacity(isActive ? 1.0 : 0.3))
                            .frame(
                                width: geo.size.width * CGFloat(cat.value / maxValue),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                // Value label
                Text(formatCurrency(cat.value))
                    .font(.caption2)
                    .fontWeight(isSelected ? .bold : .medium)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? cat.color.opacity(0.10) : Color.clear)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedCategory)
        }
        .buttonStyle(.plain)
        .disabled(isOther)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
}
