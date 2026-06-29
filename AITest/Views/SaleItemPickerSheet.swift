import SwiftUI
import SwiftData

struct SaleItemPickerSheet: View {
    let onItemSelected: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    @State private var searchText = ""

    private var filteredItems: [InventoryItem] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return allItems }
        return allItems.filter {
            $0.name.localizedCaseInsensitiveContains(t) ||
            $0.sku.localizedCaseInsensitiveContains(t) ||
            ($0.storage?.name.localizedCaseInsensitiveContains(t) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    ContentUnavailableView {
                        Label("No Items Yet", systemImage: "cube.box")
                    } description: {
                        Text("Add items to your inventory first, then you can record sales against them.")
                    }
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredItems, id: \.id) { item in
                        Button {
                            onItemSelected(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                Circle()
                                    .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline).fontWeight(.medium)
                                    Text("\(item.storage?.name ?? "No Storage")\(item.sku.isEmpty ? "" : " · \(item.sku)")")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(item.currentQuantity.smartFormatted)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundColor(item.isOutOfStock ? .red : item.isLowStock ? .orange : .secondary)
                                    Text(item.uom?.symbol ?? "units").font(.caption2).foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("saleItemRow_\(item.sku)")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search items or storages…")
        }
    }
}
