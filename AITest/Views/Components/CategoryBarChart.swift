import SwiftUI

struct CategoryBarChart: View {
    let items: [InventoryItem]
    var selectedCategory: String? = nil
    var onCategoryTapped: ((String) -> Void)? = nil

    private struct CategoryData: Identifiable {
        let id: String
        let name: String
        let count: Int
        let color: Color
    }

    private static let colors: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink
    ]

    private var categories: [CategoryData] {
        let grouped = Dictionary(grouping: items, by: \.category)
        let sorted = grouped
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        var result: [CategoryData] = []
        for (index, entry) in sorted.prefix(5).enumerated() {
            result.append(CategoryData(
                id: entry.name,
                name: entry.name,
                count: entry.count,
                color: Self.colors[index % Self.colors.count]
            ))
        }
        let otherCount = sorted.dropFirst(5).reduce(0) { $0 + $1.count }
        if otherCount > 0 {
            result.append(CategoryData(id: "__other__", name: "Other", count: otherCount, color: .gray))
        }
        return result
    }

    private var maxCount: Int {
        categories.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Items by Category")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if items.isEmpty {
                Text("No items yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(categories) { cat in
                        categoryRow(cat)
                    }
                }
                .padding(.horizontal, 4)

                Text(selectedCategory == nil ? "Tap a category to filter" : "Tap again to clear filter")
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

    @ViewBuilder
    private func categoryRow(_ cat: CategoryData) -> some View {
        let isSelected = selectedCategory == cat.id
        let isActive = selectedCategory == nil || isSelected

        if let callback = onCategoryTapped {
            Button {
                callback(cat.name)
            } label: {
                rowContent(cat: cat, isSelected: isSelected, isActive: isActive)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(cat: cat, isSelected: isSelected, isActive: isActive)
        }
    }

    @ViewBuilder
    private func rowContent(cat: CategoryData, isSelected: Bool, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(cat.color)
                .frame(width: 8, height: 8)

            Text(cat.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(minWidth: 80, maxWidth: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cat.color.opacity(isActive ? 1.0 : 0.3))
                        .frame(
                            width: geo.size.width * CGFloat(cat.count) / CGFloat(maxCount),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            Text("\(cat.count)")
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundColor(.primary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? cat.color.opacity(0.10) : Color.clear)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedCategory)
    }
}
