import SwiftUI

enum FilterType {
    case lowStock
    case outOfStock
    case allItems
    case expiringSoon
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

    private var emptyFilterIcon: String {
        switch filterType {
        case .lowStock: return "exclamationmark.triangle"
        case .outOfStock: return "xmark.circle"
        case .expiringSoon: return "calendar.badge.exclamationmark"
        case .allItems: return "cube.box"
        }
    }

    private var emptyFilterColor: Color {
        switch filterType {
        case .lowStock: return .orange
        case .outOfStock: return .red
        case .expiringSoon: return .orange
        case .allItems: return .gray
        }
    }

    private var emptyFilterTitle: String {
        switch filterType {
        case .lowStock: return "No low stock items"
        case .outOfStock: return "No out of stock items"
        case .expiringSoon: return "No expiring items"
        case .allItems: return "No items"
        }
    }

    private var emptyFilterSubtitle: String {
        switch filterType {
        case .lowStock: return "All items are well stocked"
        case .outOfStock: return "All items are in stock"
        case .expiringSoon: return "No items expiring in the next 7 days"
        case .allItems: return "Add items to get started"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: emptyFilterIcon)
                            .font(.system(size: 48))
                            .foregroundColor(emptyFilterColor)
                        
                        Text(emptyFilterTitle)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text(emptyFilterSubtitle)
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
    let title: String
    let items: [InventoryItem]
    let filterType: FilterType
    
    @State private var searchText = ""
    @State private var selectedStorage: Storage?
    
    private var filterManager: ItemFilterManager {
        ItemFilterManager(
            items: items,
            searchText: searchText,
            selectedStorage: selectedStorage
        )
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
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
                    Text("Current: \(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if item.isLowStock {
                        Text("Min: \(item.minQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
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
} 