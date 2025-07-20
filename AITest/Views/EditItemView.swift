import SwiftUI
import SwiftData

struct EditItemView: View {
    let item: InventoryItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    
    @State private var name: String
    @State private var description: String
    @State private var sku: String
    @State private var barcode: String
    @State private var currentQuantity: String
    @State private var minQuantity: String
    @State private var maxQuantity: String
    @State private var unitCost: String
    @State private var selectedStorage: Storage?
    @State private var selectedUOM: UOM?
    @State private var isOutOfStock: Bool
    
    init(item: InventoryItem) {
        self.item = item
        self._name = State(initialValue: item.name)
        self._description = State(initialValue: item.itemDescription)
        self._sku = State(initialValue: item.sku)
        self._barcode = State(initialValue: item.barcode)
        self._currentQuantity = State(initialValue: String(format: "%.2f", item.currentQuantity))
        self._minQuantity = State(initialValue: String(format: "%.2f", item.minQuantity))
        self._maxQuantity = State(initialValue: String(format: "%.2f", item.maxQuantity))
        self._unitCost = State(initialValue: String(format: "%.2f", item.unitCost))
        self._selectedStorage = State(initialValue: item.storage)
        self._selectedUOM = State(initialValue: item.uom)
        self._isOutOfStock = State(initialValue: item.isOutOfStock)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $name)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU", text: $sku)
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
                
                Section(header: Text("Quantities")) {
                    HStack {
                        Text("Current Quantity")
                        Spacer()
                        TextField("0.0", text: $currentQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Minimum Quantity")
                        Spacer()
                        TextField("0.0", text: $minQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Maximum Quantity")
                        Spacer()
                        TextField("0.0", text: $maxQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Cost")) {
                    HStack {
                        Text("Unit Cost")
                        Spacer()
                        TextField("0.00", text: $unitCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Stock Status")) {
                    Toggle("Mark as Out of Stock", isOn: $isOutOfStock)
                    
                    if !isOutOfStock {
                        HStack {
                            Text("Stock Status")
                            Spacer()
                            Text(item.stockStatus)
                                .fontWeight(.medium)
                                .foregroundColor(stockStatusColor)
                        }
                    }
                }
                
                Section(header: Text("Item Statistics")) {
                    HStack {
                        Text("Total Value")
                        Spacer()
                        Text("$\(String(format: "%.2f", item.totalValue))")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Last Updated")
                        Spacer()
                        Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(name.isEmpty || currentQuantity.isEmpty)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    private var stockStatusColor: Color {
        if item.isOutOfStock {
            return .red
        } else if item.isLowStock {
            return .orange
        } else {
            return .green
        }
    }
    
    private func saveItem() {
        item.name = name
        item.itemDescription = description
        item.sku = sku.isEmpty ? "SKU-\(UUID().uuidString.prefix(6))" : sku
        item.barcode = barcode
        item.currentQuantity = Double(currentQuantity) ?? 0
        item.minQuantity = Double(minQuantity) ?? 0
        item.maxQuantity = Double(maxQuantity) ?? 0
        item.unitCost = Double(unitCost) ?? 0
        item.storage = selectedStorage
        item.uom = selectedUOM
        item.isOutOfStock = isOutOfStock
        item.updatedAt = Date()
        
        try? modelContext.save()
        
        // Track completion for ad system
        AdManager.shared.recordCompletion(event: .itemUpdated)
        
        dismiss()
    }
}

#Preview {
    let item = InventoryItem(name: "Sample Item", description: "Sample description", sku: "SKU123", currentQuantity: 10, minQuantity: 5, maxQuantity: 20, unitCost: 15.99)
    return EditItemView(item: item)
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 