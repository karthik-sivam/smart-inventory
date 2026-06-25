import SwiftUI

struct ValueByCategoryView: View {
    let items: [InventoryItem]
    @EnvironmentObject private var currencyManager: CurrencyManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String? = nil

    private var categoryData: [(category: String, value: Double)] {
        var map: [String: Double] = [:]
        for item in items {
            map[item.category, default: 0] += item.totalValue
        }
        return map.map { (category: $0.key, value: $0.value) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    private var totalValue: Double {
        categoryData.reduce(0) { $0 + $1.value }
    }

    private var selectedItems: [InventoryItem] {
        guard let cat = selectedCategory else { return [] }
        return items.filter { $0.category == cat && $0.totalValue > 0 }
            .sorted { $0.totalValue > $1.totalValue }
    }

    private func sliceColor(_ index: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .green, .orange, .red, .teal, .pink, .indigo]
        return palette[index % palette.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        ForEach(Array(categoryData.enumerated()), id: \.element.category) { index, data in
                            PieSlice(
                                startAngle: startAngle(for: index),
                                endAngle: endAngle(for: index),
                                color: sliceColor(index),
                                isSelected: selectedCategory == data.category
                            )
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    selectedCategory = selectedCategory == data.category ? nil : data.category
                                }
                            }
                        }

                        VStack(spacing: 2) {
                            Text(selectedCategory ?? "Total")
                                .font(.caption).foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(currencyManager.formatPrice(
                                selectedCategory == nil ? totalValue :
                                categoryData.first(where: { $0.category == selectedCategory })?.value ?? 0
                            ))
                            .font(.headline).fontWeight(.bold)
                        }
                    }
                    .frame(width: 220, height: 220)
                    .padding(.top, 16)

                    VStack(spacing: 0) {
                        ForEach(Array(categoryData.enumerated()), id: \.element.category) { index, data in
                            let pct = totalValue > 0 ? (data.value / totalValue * 100) : 0
                            HStack {
                                Circle()
                                    .fill(sliceColor(index))
                                    .frame(width: 10, height: 10)
                                Text(data.category)
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1f%%", pct))
                                    .font(.caption).foregroundColor(.secondary)
                                Text(currencyManager.formatPrice(data.value))
                                    .font(.subheadline).fontWeight(.medium)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(selectedCategory == data.category ? Color(.systemGray6) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    selectedCategory = selectedCategory == data.category ? nil : data.category
                                }
                            }

                            Divider().padding(.leading, 36)
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)

                    if let cat = selectedCategory, !selectedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Items in \(cat)")
                                .font(.headline).fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)

                            ForEach(selectedItems, id: \.id) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.subheadline).fontWeight(.medium)
                                        Text(item.storage?.name ?? "No Storage")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(currencyManager.formatPrice(item.totalValue))
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text("\(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "units") × \(currencyManager.formatPrice(item.unitCost))")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)

                                Divider().padding(.leading, 20)
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Value by Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func fraction(for index: Int) -> Double {
        guard totalValue > 0 else { return 0 }
        return categoryData[index].value / totalValue
    }

    private func startAngle(for index: Int) -> Angle {
        let fractions = (0..<index).map { fraction(for: $0) }
        return Angle(degrees: fractions.reduce(0, +) * 360 - 90)
    }

    private func endAngle(for index: Int) -> Angle {
        startAngle(for: index) + Angle(degrees: fraction(for: index) * 360)
    }
}

private struct PieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2
            let innerRadius = radius * 0.52

            Path { path in
                path.move(to: centre)
                path.addArc(
                    center: centre,
                    radius: radius * (isSelected ? 1.06 : 1.0),
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(color)

            Path { path in
                path.addArc(
                    center: centre,
                    radius: innerRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360),
                    clockwise: false
                )
            }
            .fill(Color(.systemGroupedBackground))
        }
    }
}
