import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    @StateObject private var viewModel = ItemListViewModel()
    @State private var showingAddItem = false
    @State private var showingExport = false
    @State private var showingEditItem: InventoryItem?
    @State private var showingDeleteAlert: InventoryItem?
    @State private var showingQuickCount: InventoryItem? = nil
    @State private var showingFullCount: InventoryItem? = nil
    @State private var pendingFullCountItem: InventoryItem? = nil
    
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
                        .accessibilityLabel("Export Data")
                        
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
                            Button(action: { viewModel.setSelectedStorage(nil) }) {
                                Text("All Storages")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(viewModel.selectedStorage == nil ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(viewModel.selectedStorage == nil ? .white : .primary)
                                    .cornerRadius(16)
                            }
                            
                            ForEach(storages, id: \.id) { storage in
                                Button(action: { viewModel.setSelectedStorage(storage) }) {
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
                                    .background(viewModel.selectedStorage?.id == storage.id ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(viewModel.selectedStorage?.id == storage.id ? .white : .primary)
                                    .cornerRadius(16)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    SearchBar(text: $viewModel.searchText, placeholder: "Search items...")
                        .onChange(of: viewModel.searchText) { newValue in
                            viewModel.setSearchText(newValue)
                        }
                        .padding(.horizontal)
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.filteredItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "cube.box")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text(viewModel.searchText.isEmpty ? "No items found" : "No items match your search")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                if viewModel.searchText.isEmpty && viewModel.selectedStorage == nil {
                                    Text("Add items to your storages to get started")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(viewModel.filteredItems.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                                                            HStack {
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemRowView(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                VStack(spacing: 8) {
                                    Button(action: {
                                        showingEditItem = item
                                    }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    }

                                    Button(action: {
                                        showingQuickCount = item
                                    }) {
                                        Image(systemName: "list.clipboard.fill")
                                            .font(.title2)
                                            .foregroundColor(.green)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    }

                                    Button(action: {
                                        showingDeleteAlert = item
                                    }) {
                                        Image(systemName: "trash.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.red)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    }
                                }
                                .padding(.leading, 8)
                            }
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
        .sheet(item: $showingEditItem) { item in
            EditItemView(item: item)
        }
        .sheet(item: $showingQuickCount, onDismiss: {
            if let pending = pendingFullCountItem {
                pendingFullCountItem = nil
                showingFullCount = pending
            }
        }) { item in
            QuickCountView(item: item, onOpenFullCount: {
                pendingFullCountItem = item
            })
        }
        .sheet(item: $showingFullCount) { item in
            CountItemView(item: item)
        }
        .alert("Delete Item", isPresented: Binding(
            get: { showingDeleteAlert != nil },
            set: { if !$0 { showingDeleteAlert = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                showingDeleteAlert = nil
            }
            Button("Delete", role: .destructive) {
                if let item = showingDeleteAlert {
                    viewModel.deleteItem(item)
                }
                showingDeleteAlert = nil
            }
        } message: {
            if let item = showingDeleteAlert {
                Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            viewModel.bind(modelContext: modelContext, items: items, storages: storages)
        }
        .onChange(of: items) { newItems in
            viewModel.updateItems(newItems)
        }
        .onChange(of: storages) { newStorages in
            viewModel.updateStorages(newStorages)
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
    @StateObject private var formVM = ItemFormViewModel()
    @State private var showingItemLimitPaywall = false

    private var selectedStorageItemCount: Int {
        formVM.selectedStorage?.items.count ?? 0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $formVM.name)
                    TextField("Description (Optional)", text: $formVM.description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU (Optional)", text: $formVM.sku)
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
                
                Section(header: Text("Quantity & Pricing")) {
                    TextField("Current Quantity", text: $formVM.currentQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Min Quantity", text: $formVM.minQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Max Quantity", text: $formVM.maxQuantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Unit Cost", text: $formVM.unitCost)
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
                        if SubscriptionManager.shared.canAddItem(currentItemCount: selectedStorageItemCount) {
                            formVM.saveNew()
                            dismiss()
                        } else {
                            showingItemLimitPaywall = true
                        }
                    }
                    .disabled(!formVM.canSaveNew)
                }
            }
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView()
        }
        .onAppear {
            formVM.bind(modelContext: modelContext)
            if formVM.selectedUOM == nil, let defaultUOM = uoms.first(where: { $0.isDefault }) {
                formVM.selectedUOM = defaultUOM
            }
        }
    }
}

#Preview {
    ItemListView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 