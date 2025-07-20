import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    @Query private var items: [InventoryItem]
    @Query private var uoms: [UOM]
    @StateObject private var currencyManager = CurrencyManager()
    @State private var showingSettings = false
    @State private var showingExport = false
    @State private var selectedTab = 0
    @State private var showingStorages = false
    @State private var showingAllItems = false
    @State private var showingLowStockItems = false
    @State private var showingOutOfStockItems = false
    

    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smart Inventory")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Manage your inventory efficiently")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: { showingExport = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                ScrollView {
                    VStack(spacing: 16) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                            DashboardCard(
                                title: "Total Storages",
                                value: "\(storages.count)",
                                icon: "archivebox",
                                color: .blue,
                                action: { showingStorages = true }
                            )
                            
                            DashboardCard(
                                title: "Total Items",
                                value: "\(items.count)",
                                icon: "cube.box",
                                color: .green,
                                action: { showingAllItems = true }
                            )
                            
                            DashboardCard(
                                title: "Low Stock Items",
                                value: "\(lowStockItems.count)",
                                icon: "exclamationmark.triangle",
                                color: .orange,
                                action: { showingLowStockItems = true }
                            )
                            
                            DashboardCard(
                                title: "Out of Stock",
                                value: "\(outOfStockItems.count)",
                                icon: "xmark.circle",
                                color: .red,
                                action: { showingOutOfStockItems = true }
                            )
                            
                            DashboardCard(
                                title: "Total Value",
                                value: currencyManager.formatPrice(totalInventoryValue),
                                icon: "dollarsign.circle",
                                color: .purple,
                                action: nil
                            )
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Activity")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            if items.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "cube.box")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                    Text("No items yet")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    Text("Start by creating a storage area and adding items")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(items.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(5), id: \.id) { item in
                                        RecentActivityRow(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
                

            }
            .navigationBarHidden(true)
        }
        .onAppear {
            initializeStandardUOMs()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(currencyManager)
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
        }
        .sheet(isPresented: $showingStorages) {
            StorageListView()
                .environmentObject(currencyManager)
        }
        .sheet(isPresented: $showingAllItems) {
            ItemListView()
                .environmentObject(currencyManager)
        }
        .sheet(isPresented: $showingLowStockItems) {
            FilteredItemListView(
                title: "Low Stock Items",
                items: lowStockItems,
                filterType: .lowStock
            )
            .environmentObject(currencyManager)
        }
        .sheet(isPresented: $showingOutOfStockItems) {
            FilteredItemListView(
                title: "Out of Stock Items",
                items: outOfStockItems,
                filterType: .outOfStock
            )
            .environmentObject(currencyManager)
        }
    }
    
    private var lowStockItems: [InventoryItem] {
        items.filter { $0.isLowStock }
    }
    
    private var outOfStockItems: [InventoryItem] {
        items.filter { $0.isOutOfStock }
    }
    
    private var totalInventoryValue: Double {
        items.reduce(0) { $0 + $1.totalValue }
    }
    
    private func initializeStandardUOMs() {
        if uoms.isEmpty {
            for standardUOM in UOM.standardUOMs {
                modelContext.insert(standardUOM)
            }
            try? modelContext.save()
        }
    }
}

struct DashboardCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            action?()
        }
        .scaleEffect(action != nil ? 1.0 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: action != nil)
    }
}

struct RecentActivityRow: View {
    let item: InventoryItem
    
    var body: some View {
                                HStack {
                            Circle()
                                .fill(item.isOutOfStock ? Color.red : (item.isLowStock ? Color.orange : Color.green))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(item.storage?.name ?? "No Storage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(String(format: "%.1f", item.currentQuantity)) \(item.uom?.symbol ?? "")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(item.stockStatus)
                                    .font(.caption)
                                    .foregroundColor(item.isOutOfStock ? .red : (item.isLowStock ? .orange : .green))
                            }
                        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}



#Preview {
    DashboardView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 