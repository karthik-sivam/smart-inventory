import SwiftUI
import SwiftData

struct EditItemView: View {
    let item: InventoryItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    @StateObject private var formVM = ItemFormViewModel()
    
    init(item: InventoryItem) {
        self.item = item
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $formVM.name)
                    TextField("Description (Optional)", text: $formVM.description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU", text: $formVM.sku)
                    TextField("Barcode (Optional)", text: $formVM.barcode)
                }
                
                Section(header: Text("Storage & UOM")) {
                    Picker("Storage", selection: $formVM.selectedStorage) {
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
                    
                    Picker("Unit of Measure", selection: $formVM.selectedUOM) {
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
                        TextField("0.0", text: $formVM.currentQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Minimum Quantity")
                        Spacer()
                        TextField("0.0", text: $formVM.minQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Maximum Quantity")
                        Spacer()
                        TextField("0.0", text: $formVM.maxQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Cost")) {
                    HStack {
                        Text("Unit Cost")
                        Spacer()
                        TextField("0.00", text: $formVM.unitCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Stock Status")) {
                    Toggle("Mark as Out of Stock", isOn: $formVM.isOutOfStock)
                    
                    if !formVM.isOutOfStock {
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
                        formVM.saveEdits(to: item)
                        dismiss()
                    }
                    .disabled(!formVM.canSaveEdit)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            formVM.bind(modelContext: modelContext)
            formVM.load(from: item)
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
    
}

#Preview {
    let item = InventoryItem(name: "Sample Item", description: "Sample description", sku: "SKU123", currentQuantity: 10, minQuantity: 5, maxQuantity: 20, unitCost: 15.99)
    return EditItemView(item: item)
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 