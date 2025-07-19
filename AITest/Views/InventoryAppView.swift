import SwiftUI
import SwiftData

struct InventoryAppView: View {
    @State private var selectedTab = 0
    @StateObject private var currencyManager = CurrencyManager()
    
    var body: some View {
        AdIntegrationView {
            ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    DashboardView()
                        .environmentObject(currencyManager)
                case 1:
                    StorageListView()
                        .environmentObject(currencyManager)
                case 2:
                    ItemListView()
                        .environmentObject(currencyManager)
                case 3:
                    CountView()
                        .environmentObject(currencyManager)
                default:
                    DashboardView()
                        .environmentObject(currencyManager)
                }
            }
            
            // Custom Bottom Tab Bar
            VStack {
                Spacer()
                
                HStack(spacing: 0) {
                    TabBarButton(
                        icon: "house.fill",
                        title: "Dashboard",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }
                    
                    TabBarButton(
                        icon: "archivebox.fill",
                        title: "Storages",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }
                    
                    TabBarButton(
                        icon: "cube.box.fill",
                        title: "Items",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                    
                    TabBarButton(
                        icon: "list.clipboard.fill",
                        title: "Count",
                        isSelected: selectedTab == 3
                    ) {
                        selectedTab = 3
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .gray)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    
    @State private var searchText = ""
    @State private var selectedStorage: Storage?
    @State private var showingCountModal = false
    @State private var selectedItem: InventoryItem?
    
    var filteredItems: [InventoryItem] {
        var result = items
        
        if let selectedStorage = selectedStorage {
            result = result.filter { $0.storage?.id == selectedStorage.id }
        }
        
        if !searchText.isEmpty {
            result = result.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) || 
                $0.sku.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Inventory Count")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if !filteredItems.isEmpty {
                        Button(action: { showingCountModal = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                // Filter and Search
                VStack(spacing: 12) {
                    // Storage Filter
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
                            
                            ForEach(storages, id: \.id) { storage in
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
                    
                    // Search Bar
                    SearchBar(text: $searchText, placeholder: "Search items to count...")
                        .padding(.horizontal)
                }
                
                // Items List for Counting
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "list.clipboard")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text("No items to count")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text("Add items to your storages to start counting")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(filteredItems.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                                Button(action: {
                                    selectedItem = item
                                    showingCountModal = true
                                }) {
                                    CountItemCard(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .padding(.top, 16)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingCountModal) {
            if let item = selectedItem {
                CountItemView(item: item)
                    .onDisappear {
                        selectedItem = nil
                    }
            }
        }
    }
}

struct CountItemCard: View {
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
                
                Text("Current: \(String(format: "%.1f", item.currentQuantity)) \(item.uom?.symbol ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "list.clipboard")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Count")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    InventoryAppView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 