import SwiftUI
import SwiftData

struct ReorderListView: View {
    let items: [InventoryItem]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: InventoryItem? = nil

    private var sortedItems: [InventoryItem] {
        items.sorted {
            let deficitA = max(0, $0.effectiveMinQuantity - $0.currentQuantity)
            let deficitB = max(0, $1.effectiveMinQuantity - $1.currentQuantity)
            if $0.isOutOfStock != $1.isOutOfStock { return $0.isOutOfStock }
            return deficitA > deficitB
        }
    }

    private var storageGroups: [(storage: Storage, items: [InventoryItem])] {
        var seen: [UUID: (Storage, [InventoryItem])] = [:]
        for item in sortedItems {
            guard let storage = item.storage else { continue }
            if seen[storage.id] == nil {
                seen[storage.id] = (storage, [])
            }
            seen[storage.id]!.1.append(item)
        }
        return seen.values
            .filter { !$0.0.supplierEmail.isEmpty }
            .sorted { $0.0.name < $1.0.name }
    }

    private func buildMailtoURL(storage: Storage, items: [InventoryItem]) -> URL? {
        guard !storage.supplierEmail.isEmpty else { return nil }
        let subject = "Restock Request — \(storage.name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let lines = items.map { item in
            let deficit = max(0, item.effectiveMinQuantity - item.currentQuantity)
            let uomLabel = item.uom?.symbol ?? "units"
            return "  • \(item.name): need \(deficit.smartFormatted) \(uomLabel)"
        }
        let bodyText = "Hi,\n\nPlease restock the following items from \(storage.name):\n\n"
            + lines.joined(separator: "\n")
            + "\n\nThank you."
        let body = bodyText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(storage.supplierEmail)?subject=\(subject)&body=\(body)")
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.stoqlySuccess)
                        Text("All stocked up!")
                            .font(.title3).fontWeight(.medium)
                        Text("No items are below their minimum quantity.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(storageGroups, id: \.storage.id) { group in
                                if let url = buildMailtoURL(storage: group.storage, items: group.items) {
                                    Button {
                                        UIApplication.shared.open(url)
                                    } label: {
                                        Label("Email \(group.storage.name) Supplier", systemImage: "envelope")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                }
                            }

                            HStack {
                                Text("\(sortedItems.count) item\(sortedItems.count == 1 ? "" : "s") to restock")
                                    .font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            LazyVStack(spacing: 1) {
                                ForEach(sortedItems, id: \.id) { item in
                                    ReorderRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedItem = item }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)

                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reorder List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                AnalyticsManager.shared.track(.reorderListViewed(itemCount: sortedItems.count))
            }
            .sheet(item: $selectedItem) { item in
                ReorderItemDetailSheet(item: item)
                    .sheetStyle()
            }
        }
    }
}

private struct ReorderItemDetailSheet: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ItemDetailView(item: item)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") { dismiss() }
                    }
                }
        }
    }
}

struct ReorderRowView: View {
    let item: InventoryItem

    private var deficit: Double {
        max(0, item.effectiveMinQuantity - item.currentQuantity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline).fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text(item.isOutOfStock ? "Out of Stock" : "Low Stock")
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(item.isOutOfStock ? Color.stoqlyDanger.opacity(0.12) : Color.stoqlyWarning.opacity(0.12))
                            .foregroundColor(item.isOutOfStock ? .red : .orange)
                            .cornerRadius(4)

                        Text(item.storage?.name ?? "No Storage")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Need \(deficit.smartFormatted)\(item.uom.map { " \($0.symbol)" } ?? "")")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Have: \(item.currentQuantity.smartFormatted) / Min: \(item.effectiveMinQuantity.smartFormatted)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                Text("View & Count →")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.stoqlyPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
