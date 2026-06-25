import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [InventoryItem]
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @StateObject private var historyManager = SearchHistoryManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search items, SKUs, barcodes...", text: $searchText)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { historyManager.record(searchText) }
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if searchText.isEmpty && !historyManager.queries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(historyManager.queries, id: \.self) { query in
                                Button(action: { searchText = query }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.caption2)
                                        Text(query)
                                            .font(.subheadline)
                                        Button(action: { historyManager.remove(query) }) {
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.primary)
                            }
                            if !historyManager.queries.isEmpty {
                                Button("Clear") { historyManager.clear() }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 4)
                }

                Divider()

                if searchText.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Search across all storages")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Name, SKU, barcode, category, description, location")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No results for \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Try a different name, SKU, or barcode.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults, id: \.id) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    SearchResultRow(item: item, query: searchText)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    historyManager.record(searchText)
                                })
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private var searchResults: [InventoryItem] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(q) ||
            $0.sku.lowercased().contains(q) ||
            $0.barcode.lowercased().contains(q) ||
            $0.itemDescription.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            ($0.storage?.name.lowercased().contains(q) ?? false) ||
            ($0.storage?.location.lowercased().contains(q) ?? false)
        }
        .sorted {
            relevanceScore($0, query: searchText) > relevanceScore($1, query: searchText)
        }
    }

    private func relevanceScore(_ item: InventoryItem, query: String) -> Double {
        let q = query.lowercased()
        var score: Double = 0
        if item.name.lowercased() == q {
            score += 4
        } else if item.name.lowercased().hasPrefix(q) {
            score += 3
        } else if item.name.lowercased().contains(q) {
            score += 1
        }
        if item.sku.lowercased() == q { score += 2 }
        if item.barcode.lowercased().contains(q) { score += 1 }
        if item.itemDescription.lowercased().contains(q) { score += 1 }
        if item.category.lowercased().contains(q) { score += 1 }
        if item.storage?.name.lowercased().contains(q) == true { score += 1 }
        if item.isLowStock || item.isOutOfStock { score += 0.5 }
        return score
    }
}

struct SearchResultRow: View {
    let item: InventoryItem
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.isOutOfStock ? Color.red : (item.isLowStock ? Color.orange : Color.green))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    if item.category != "Uncategorised" {
                        Text(item.category)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                            .foregroundColor(.secondary)
                    }
                    Text(item.storage?.name ?? "No Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.currentQuantity.smartFormatted)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(item.uom?.symbol ?? "units")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .accessibilityHint("Search text: \(query)")
    }
}
