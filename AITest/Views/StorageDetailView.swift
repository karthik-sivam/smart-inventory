import SwiftUI
import SwiftData

struct StorageDetailView: View {
    let storage: Storage
    
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showingAddItem = false
    
    var filteredItems: [InventoryItem] {
        if searchText.isEmpty {
            return storage.items
        } else {
            return storage.items.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) || 
                $0.sku.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(storage.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !storage.location.isEmpty {
                        Text(storage.location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { showingAddItem = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            HStack(spacing: 20) {
                StatCard(title: "Total Items", value: "\(storage.itemCount)", color: .blue)
                StatCard(title: "Total Quantity", value: String(format: "%.1f", storage.totalQuantity), color: .green)
                StatCard(title: "Low Stock", value: "\(lowStockCount)", color: .orange)
            }
            .padding(.horizontal)
            
            SearchBar(text: $searchText, placeholder: "Search items...")
                .padding(.horizontal)
                .padding(.top, 16)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text(searchText.isEmpty ? "No items in this storage" : "No items found")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            if searchText.isEmpty {
                                Text("Add your first item to this storage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(filteredItems, id: \.id) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
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
        .sheet(isPresented: $showingAddItem) {
            AddItemView(storage: storage)
        }
    }
    
    private var lowStockCount: Int {
        storage.items.filter { $0.isLowStock }.count
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

struct ItemCard: View {
    let item: InventoryItem
    
    var body: some View {
        HStack(spacing: 12) {
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
                    
                    Text(item.stockStatus)
                        .font(.caption)
                        .foregroundColor(item.isOutOfStock ? .red : (item.isLowStock ? .orange : .green))
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
                
                if item.unitCost > 0 {
                    Text("$\(String(format: "%.2f", item.totalValue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct AddItemView: View {
    let storage: Storage
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var uoms: [UOM]
    
    @State private var name = ""
    @State private var description = ""
    @State private var sku = ""
    @State private var barcode = ""
    @State private var currentQuantity = ""
    @State private var minQuantity = ""
    @State private var maxQuantity = ""
    @State private var unitCost = ""
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
                
                Section(header: Text("Quantity & Pricing")) {
                    HStack {
                        TextField("Current Quantity", text: $currentQuantity)
                            .keyboardType(.decimalPad)
                        
                        Picker("UOM", selection: $selectedUOM) {
                            Text("Select UOM").tag(nil as UOM?)
                            ForEach(uoms, id: \.id) { uom in
                                Text("\(uom.name) (\(uom.symbol))").tag(uom as UOM?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    TextField("Min Quantity", text: $minQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Max Quantity", text: $maxQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Unit Cost", text: $unitCost)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Storage Location")) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: storage.color) ?? .blue)
                            .frame(width: 20, height: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(storage.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if !storage.location.isEmpty {
                                Text(storage.location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
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
                    .disabled(name.isEmpty || selectedUOM == nil)
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
            storage: storage,
            uom: selectedUOM
        )
        
        modelContext.insert(item)
        try? modelContext.save()
        
        // Track completion for ad system
        AdManager.shared.recordCompletion(event: .itemAdded)
        
        dismiss()
    }
}

struct ItemDetailView: View {
    let item: InventoryItem
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingCountModal = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("SKU: \(item.sku)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingCountModal = true }) {
                    Image(systemName: "list.clipboard")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Current Status
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text("\(String(format: "%.1f", item.currentQuantity))")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text(item.uom?.symbol ?? "units")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Current Stock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        
                        VStack(spacing: 8) {
                            Text(item.stockStatus)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(item.isOutOfStock ? .red : (item.isLowStock ? .orange : .green))
                            
                            if item.unitCost > 0 {
                                Text("$\(String(format: "%.2f", item.totalValue))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Status")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                    .padding(.horizontal)
                    
                    // Out of Stock Toggle
                    HStack {
                        Label("Out of Stock", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { item.isOutOfStock },
                            set: { newValue in
                                item.isOutOfStock = newValue
                                item.updatedAt = Date()
                                try? modelContext.save()
                                
                                // Track completion for ad system
                                AdManager.shared.recordCompletion(event: .itemUpdated)
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .red))
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    .padding(.horizontal)
                    
                    // Item Details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Item Details")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            DetailRow(label: "Name", value: item.name)
                            DetailRow(label: "Description", value: item.itemDescription.isEmpty ? "N/A" : item.itemDescription)
                            DetailRow(label: "SKU", value: item.sku)
                            DetailRow(label: "Barcode", value: item.barcode.isEmpty ? "N/A" : item.barcode)
                            DetailRow(label: "Storage", value: item.storage?.name ?? "N/A")
                            DetailRow(label: "UOM", value: item.uom?.name ?? "N/A")
                            DetailRow(label: "Min Quantity", value: String(format: "%.1f", item.minQuantity))
                            DetailRow(label: "Max Quantity", value: String(format: "%.1f", item.maxQuantity))
                            DetailRow(label: "Unit Cost", value: "$\(String(format: "%.2f", item.unitCost))")
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.vertical)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingCountModal) {
            CountItemView(item: item)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct CountItemView: View {
    let item: InventoryItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var countedQuantity = ""
    @State private var adjustmentReason = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current Information")) {
                    HStack {
                        Text("Current Quantity:")
                        Spacer()
                        Text("\(String(format: "%.1f", item.currentQuantity)) \(item.uom?.symbol ?? "")")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Last Updated:")
                        Spacer()
                        Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .fontWeight(.medium)
                    }
                }
                
                Section(header: Text("New Count")) {
                    TextField("Counted Quantity", text: $countedQuantity)
                        .keyboardType(.decimalPad)
                    
                    Picker("Adjustment Reason", selection: $adjustmentReason) {
                        Text("Select reason").tag("")
                        Text("Physical Count").tag("Physical Count")
                        Text("Damaged").tag("Damaged")
                        Text("Expired").tag("Expired")
                        Text("Sold").tag("Sold")
                        Text("Received").tag("Received")
                        Text("Transferred").tag("Transferred")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    TextField("Notes (Optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
                
                if let newQuantity = Double(countedQuantity) {
                    Section(header: Text("Adjustment Preview")) {
                        HStack {
                            Text("Variance:")
                            Spacer()
                            Text("\(String(format: "%.1f", newQuantity - item.currentQuantity))")
                                .fontWeight(.medium)
                                .foregroundColor(newQuantity > item.currentQuantity ? .green : .red)
                        }
                        
                        HStack {
                            Text("New Quantity:")
                            Spacer()
                            Text("\(String(format: "%.1f", newQuantity)) \(item.uom?.symbol ?? "")")
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .navigationTitle("Count Item")
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
                        saveCount()
                    }
                    .disabled(countedQuantity.isEmpty || adjustmentReason.isEmpty)
                }
            }
        }
    }
    
    private func saveCount() {
        guard let newQuantity = Double(countedQuantity) else { return }
        
        let count = InventoryCount(
            previousQuantity: item.currentQuantity,
            countedQuantity: newQuantity,
            adjustmentReason: adjustmentReason,
            notes: notes,
            item: item
        )
        
        // Update item quantity
        item.currentQuantity = newQuantity
        item.updatedAt = Date()
        
        modelContext.insert(count)
        try? modelContext.save()
        
        // Track completion for ad system (reward ad for major task)
        AdManager.shared.recordCompletion(event: .inventoryCountCompleted)
        
        dismiss()
    }
}

#Preview {
    let storage = Storage(name: "Sample Storage", location: "Warehouse A", description: "Sample description")
    return StorageDetailView(storage: storage)
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 