import SwiftUI
import SwiftData
import UIKit

struct EditItemView: View {
    let item: InventoryItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    @StateObject private var formVM = ItemFormViewModel()
    @StateObject private var teamManager = TeamManager.shared
    @State private var showMarkOutOfStockConfirm = false
    @State private var templateToastMessage: String? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var showingBarcodeScanner = false
    /// Stashes the scanned code while the fullScreenCover dismisses; applied
    /// in `onDismiss` so we don't mutate `formVM.barcode` in the same render
    /// pass that toggles `showingBarcodeScanner`.
    @State private var pendingScannedBarcode: String?
    @State private var usePercentThreshold = false

    init(item: InventoryItem) {
        self.item = item
    }
    
    var body: some View {
        NavigationStack {
            Form {
                ItemPhotoSection(
                    selectedPhotoData: $selectedPhotoData,
                    existingPhotoURL: formVM.existingPhotoURL
                )

                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $formVM.name)
                    TextField("Description (Optional)", text: $formVM.description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU", text: $formVM.sku)
                    HStack {
                        TextField("Barcode (Optional)", text: $formVM.barcode)
                        if formVM.barcode.isEmpty {
                            Button(action: { showingBarcodeScanner = true }) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title3)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                        }
                    }
                    // Phase 3 — Smart barcode lookup loading indicator.
                    if formVM.isEnriching {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Looking up product...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Category")) {
                    Picker("Category", selection: $formVM.category) {
                        ForEach(InventoryItem.predefinedCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(header: Text("Expiry")) {
                    Toggle("Has Expiry Date", isOn: $formVM.hasExpiryDate.animation(.easeInOut(duration: 0.2)))
                    if formVM.hasExpiryDate {
                        DatePicker(
                            "Expiry Date",
                            selection: $formVM.expiryDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        Text("You'll get a notification 3 days before this item expires.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !item.batches.isEmpty {
                        Text("This item has \(item.batches.count) batch(es) with individual expiry dates. Edit batch expiry dates from the item detail screen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    
                    Picker("Unit of Measure (UOM)", selection: $formVM.selectedUOM) {
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
                            .accessibilityIdentifier("editItemCurrentQty")
                    }
                    
                    HStack {
                        Text("Minimum Quantity")
                        Spacer()
                        TextField("0.0", text: $formVM.minQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editItemMinQty")
                    }
                    
                    HStack {
                        Text("Maximum Quantity")
                        Spacer()
                        TextField("0.0", text: $formVM.maxQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editItemMaxQty")
                    }

                    Toggle("Use percentage threshold", isOn: $usePercentThreshold)
                        .onChange(of: usePercentThreshold) { _, enabled in
                            if !enabled { formVM.reorderPercentage = 0 }
                        }
                    if usePercentThreshold {
                        let maxQ = Double(formVM.maxQuantity) ?? 0
                        if maxQ > 0 {
                            HStack {
                                Text("Reorder at")
                                Slider(value: $formVM.reorderPercentage, in: 5...75, step: 5)
                                Text("\(Int(formVM.reorderPercentage))% of max")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            Text("Set a Max Qty above to use percentage threshold.")
                                .font(.caption).foregroundColor(.secondary)
                        }
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
                    HStack {
                        Text("Last Purchase Price")
                        Spacer()
                        TextField("0.00", text: $formVM.lastPurchasePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Stock Status")) {
                    // Out of stock is computed from current quantity — use the button below to set quantity to zero.
                    HStack {
                        Text("Stock Status")
                        Spacer()
                        Text(editStockStatusLabel)
                            .fontWeight(.medium)
                            .foregroundColor(editStockStatusColor)
                    }
                    Button("Mark as Out of Stock (set quantity to 0)") {
                        showMarkOutOfStockConfirm = true
                    }
                    .disabled((Double(formVM.currentQuantity) ?? 0) <= 0)
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

                if subscriptionManager.isPro && teamManager.canEdit {
                    Section {
                        Button {
                            let template = ItemTemplate(
                                name: formVM.name,
                                description: formVM.description,
                                category: formVM.category,
                                uomSymbol: formVM.selectedUOM?.symbol ?? "pcs",
                                uomName: formVM.selectedUOM?.name ?? "Pieces",
                                defaultMinQty: Double(formVM.minQuantity) ?? 0,
                                defaultMaxQty: Double(formVM.maxQuantity) ?? 0
                            )
                            modelContext.insert(template)
                            modelContext.safeSave(context: "saveAsTemplate")
                            FirestoreManager.shared.syncTemplate(template)
                            templateToastMessage = "Saved as template"
                        } label: {
                            Label("Save as Template", systemImage: "doc.badge.plus")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                        .frame(maxWidth: .infinity)
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
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        if let photoData = selectedPhotoData {
                            let capturedItem = item
                            let ctx = modelContext
                            Task {
                                do {
                                    let url = try await FirestoreManager.shared.uploadItemPhoto(
                                        photoData, itemId: capturedItem.id
                                    )
                                    capturedItem.photoURL = url
                                    ctx.safeSave(context: "save photoURL after upload")
                                    FirestoreManager.shared.syncItem(capturedItem)
                                } catch {
                                    print("Photo upload failed: \(error.localizedDescription)")
                                }
                            }
                        }
                        dismiss()
                    }
                    .disabled(!formVM.canSaveEdit)
                }
            }
            .navigationBarBackButtonHidden(true)
            .confirmationDialog(
                "Set current quantity to zero? This marks the item as out of stock.",
                isPresented: $showMarkOutOfStockConfirm,
                titleVisibility: .visible
            ) {
                Button("Set quantity to 0", role: .destructive) {
                    formVM.currentQuantity = "0"
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            formVM.bind(modelContext: modelContext)
            formVM.load(from: item)
            usePercentThreshold = item.reorderPercentage > 0
        }
        // NOTE: must be `.fullScreenCover`, not `.sheet`. Presenting a camera
        // host as a sheet-inside-a-sheet wedges the AVFoundation capture XPC
        // (err=-17281). See the contract comment on BarcodeScannerView.
        //
        // The scanned value is stashed in `pendingScannedBarcode` and applied
        // in `onDismiss` — writing to `formVM.barcode` in the same render
        // pass as the dismissal toggle causes SwiftUI to drop the value (or
        // cascade-dismiss the parent sheet) on iOS 16/17.
        .fullScreenCover(
            isPresented: $showingBarcodeScanner,
            onDismiss: {
                if let code = pendingScannedBarcode {
                    formVM.barcode = code
                    pendingScannedBarcode = nil
                    // Phase 3 — only enrich when the user hasn't started
                    // changing the item's name yet. This protects users who
                    // are scanning a barcode INTO an existing item solely to
                    // associate the code with that record — we mustn't
                    // clobber their carefully chosen name with whatever the
                    // external database returns.
                    //
                    // Gated on `isPro` inside `enrichFromBarcode` so free
                    // users get no network call.
                    if formVM.name == item.name {
                        Task {
                            await formVM.enrichFromBarcode(code, uoms: uoms)
                        }
                    }
                }
            }
        ) {
            BarcodeScannerView(
                onScan: { code, _ in
                    pendingScannedBarcode = code
                    showingBarcodeScanner = false
                },
                onCancel: {
                    pendingScannedBarcode = nil
                    showingBarcodeScanner = false
                }
            )
            .onAppear {
                AnalyticsManager.shared.track(.barcodeScanInitiated)
            }
        }
        .toast(message: $templateToastMessage)
    }
    
    private var editStockStatusLabel: String {
        let qty = Double(formVM.currentQuantity) ?? 0
        let minQ = effectiveEditMinQuantity
        let maxQ = Double(formVM.maxQuantity) ?? 0
        if qty <= 0 { return "Out of Stock" }
        if minQ > 0 && qty > 0 && qty <= minQ { return "Low Stock" }
        if maxQ > 0 && qty >= maxQ { return "Over Stock" }
        return "In Stock"
    }

    private var editStockStatusColor: Color {
        let qty = Double(formVM.currentQuantity) ?? 0
        let minQ = effectiveEditMinQuantity
        let maxQ = Double(formVM.maxQuantity) ?? 0
        if qty <= 0 { return .red }
        if minQ > 0 && qty > 0 && qty <= minQ { return .orange }
        if maxQ > 0 && qty >= maxQ { return .yellow }
        return .green
    }

    private var effectiveEditMinQuantity: Double {
        let maxQ = Double(formVM.maxQuantity) ?? 0
        if usePercentThreshold, formVM.reorderPercentage > 0, maxQ > 0 {
            return maxQ * formVM.reorderPercentage / 100
        }
        return Double(formVM.minQuantity) ?? 0
    }
    
}

#Preview {
    let item = InventoryItem(
        name: "Sample Item",
        description: "Sample description",
        sku: "SKU123",
        currentQuantity: 10,
        minQuantity: 5,
        maxQuantity: 20,
        unitCost: 15.99
    )
    return EditItemView(item: item)
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 