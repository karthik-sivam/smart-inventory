import SwiftUI

enum FilterType {
    case lowStock
    case outOfStock
    case allItems
}

struct ItemFilterManager {
    let items: [InventoryItem]
    let searchText: String
    let selectedStorage: Storage?
    
    var availableStorages: [Storage] {
        let storages = items.compactMap { $0.storage }
        let uniqueStorages = Array(Set(storages.map { $0.id }))
        return uniqueStorages.compactMap { id in
            storages.first { $0.id == id }
        }
    }
    
    var filteredItems: [InventoryItem] {
        var result = items
        
        // Apply storage filter
        if let selectedStorage = selectedStorage {
            result = result.filter { item in
                guard let itemStorage = item.storage else { return false }
                return itemStorage.id == selectedStorage.id
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter { item in
                let nameLower = item.name.lowercased()
                let skuLower = item.sku.lowercased()
                return nameLower.contains(searchLower) || skuLower.contains(searchLower)
            }
        }
        
        return result
    }
}

struct FilterSearchView: View {
    let items: [InventoryItem]
    @Binding var searchText: String
    @Binding var selectedStorage: Storage?
    
    private var filterManager: ItemFilterManager {
        ItemFilterManager(
            items: items,
            searchText: searchText,
            selectedStorage: selectedStorage
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Storage Filter
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button(action: { selectedStorage = nil }) {
                            Text("All Storages")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedStorage == nil ? Color.blue : Color(.systemGray5))
                                .foregroundColor(selectedStorage == nil ? .white : .primary)
                                .cornerRadius(16)
                        }
                        
                        ForEach(filterManager.availableStorages, id: \.id) { storage in
                            Button(action: { selectedStorage = storage }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: storage.color) ?? .blue)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(storage.name)
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedStorage?.id == storage.id ? Color.blue : Color(.systemGray5))
                                .foregroundColor(selectedStorage?.id == storage.id ? .white : .primary)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Search Bar
            SearchBar(text: $searchText, placeholder: "Search items...")
                .padding(.horizontal)
        }
    }
}

struct ItemsListView: View {
    let items: [InventoryItem]
    let filterType: FilterType
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: filterType == .lowStock ? "exclamationmark.triangle" : "xmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(filterType == .lowStock ? .orange : .red)
                        
                        Text(filterType == .lowStock ? "No low stock items" : "No out of stock items")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text(filterType == .lowStock ? "All items are well stocked" : "All items are in stock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(items.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                        FilteredItemCard(item: item)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
        .padding(.top, 16)
    }
}

struct FilteredItemListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    
    let title: String
    let items: [InventoryItem]
    let filterType: FilterType
    
    @State private var searchText = ""
    @State private var selectedStorage: Storage?
    @State private var showingAddItem = false
    
    private var filterManager: ItemFilterManager {
        ItemFilterManager(
            items: items,
            searchText: searchText,
            selectedStorage: selectedStorage
        )
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if !filterManager.filteredItems.isEmpty {
                        Button(action: { showingAddItem = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                // Filter and Search
                FilterSearchView(
                    items: items,
                    searchText: $searchText,
                    selectedStorage: $selectedStorage
                )
                
                // Items List
                ItemsListView(
                    items: filterManager.filteredItems,
                    filterType: filterType
                )
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddItem) {
            if let storage = selectedStorage ?? filterManager.availableStorages.first {
                AddItemView(storage: storage)
                    .environmentObject(currencyManager)
            }
        }
    }
}

struct FilteredItemCard: View {
    let item: InventoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Storage color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                .frame(width: 4, height: 50)
            
            // Status indicator
            Circle()
                .fill(item.isOutOfStock ? Color.red : (item.isLowStock ? Color.orange : Color.green))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack {
                    Text("SKU: \(item.sku)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(item.storage?.name ?? "No Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Current: \(String(format: "%.1f", item.currentQuantity)) \(item.uom?.symbol ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if item.isLowStock {
                        Text("Min: \(String(format: "%.1f", item.minQuantity)) \(item.uom?.symbol ?? "")")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.stockStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(item.isOutOfStock ? .red : (item.isLowStock ? .orange : .green))
                
                Text("$\(String(format: "%.2f", item.totalValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    FilteredItemListView(
        title: "Low Stock Items",
        items: [],
        filterType: .lowStock
    )
    .environmentObject(CurrencyManager())
} 