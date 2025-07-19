import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    
    @State private var searchText = ""
    @State private var selectedStorage: Storage?
    @State private var showingAddItem = false
    @State private var showingExport = false
    
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
                HStack {
                    Text("Items")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: { showingExport = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: { showingAddItem = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                VStack(spacing: 12) {
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
                    
                    SearchBar(text: $searchText, placeholder: "Search items...")
                        .padding(.horizontal)
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "cube.box")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text(searchText.isEmpty ? "No items found" : "No items match your search")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                if searchText.isEmpty && selectedStorage == nil {
                                    Text("Add items to your storages to get started")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(filteredItems.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemRowView(item: item)
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
        .sheet(isPresented: $showingAddItem) {
            AddItemToStorageView()
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
        }
    }
}

struct ItemRowView: View {
    let item: InventoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                .frame(width: 4, height: 50)
            
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
                    Text(item.stockStatus)
                        .font(.caption)
                        .foregroundColor(item.isOutOfStock ? .red : (item.isLowStock ? .orange : .green))
                    
                    Spacer()
                    
                    if item.unitCost > 0 {
                        Text("$\(String(format: "%.2f", item.totalValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(String(format: "%.1f", item.currentQuantity))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(item.uom?.symbol ?? "units")
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

struct AddItemToStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    
    @State private var name = ""
    @State private var description = ""
    @State private var sku = ""
    @State private var barcode = ""
    @State private var currentQuantity = ""
    @State private var minQuantity = ""
    @State private var maxQuantity = ""
    @State private var unitCost = ""
    @State private var selectedStorage: Storage?
    @State private var selectedUOM: UOM?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $name)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU (Optional)", text: $sku)
                    TextField("Barcode (Optional)", text: $barcode)
                }
                
                Section(header: Text("Storage & UOM")) {
                    Picker("Storage", selection: $selectedStorage) {
                        Text("Select Storage").tag(nil as Storage?)
                        ForEach(storages, id: \.id) { storage in
                            HStack {
                                Circle()
                                    .fill(Color(hex: storage.color) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(storage.name)
                            }
                            .tag(storage as Storage?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Picker("Unit of Measure", selection: $selectedUOM) {
                        Text("Select UOM").tag(nil as UOM?)
                        ForEach(uoms, id: \.id) { uom in
                            Text("\(uom.name) (\(uom.symbol))").tag(uom as UOM?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section(header: Text("Quantity & Pricing")) {
                    TextField("Current Quantity", text: $currentQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Min Quantity", text: $minQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Max Quantity", text: $maxQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Unit Cost", text: $unitCost)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(name.isEmpty || selectedStorage == nil || selectedUOM == nil)
                }
            }
        }
        .onAppear {
            if let defaultUOM = uoms.first(where: { $0.isDefault }) {
                selectedUOM = defaultUOM
            }
        }
    }
    
    private func saveItem() {
        let item = InventoryItem(
            name: name,
            description: description,
            sku: sku,
            barcode: barcode,
            currentQuantity: Double(currentQuantity) ?? 0,
            minQuantity: Double(minQuantity) ?? 0,
            maxQuantity: Double(maxQuantity) ?? 0,
            unitCost: Double(unitCost) ?? 0,
            storage: selectedStorage,
            uom: selectedUOM
        )
        
        modelContext.insert(item)
        try? modelContext.save()
        
        // Track completion for ad system
        AdManager.shared.recordCompletion(event: .itemAdded)
        
        dismiss()
    }
}

#Preview {
    ItemListView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 