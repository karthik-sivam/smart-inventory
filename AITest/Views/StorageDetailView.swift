import SwiftUI
import SwiftData
import UIKit

struct StorageDetailView: View {
    let storage: Storage
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var currencyManager: CurrencyManager
    @StateObject private var viewModel = StorageDetailViewModel()
    @StateObject private var teamManager = TeamManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showingAddItem = false
    @State private var showingEditStorage = false
    @State private var showingQuickCount: InventoryItem? = nil
    @State private var showingFullCount: InventoryItem? = nil
    @State private var pendingFullCountItem: InventoryItem? = nil
    @State private var showingItemLimitPaywall = false
    @State private var showingEditItem: InventoryItem? = nil
    @State private var showingDeleteAlert: InventoryItem? = nil
    /// Bottom toast confirming an item deletion. Auto-clears after ~2 seconds.
    @State private var toastMessage: String? = nil
    @State private var showingSmartCount = false

    private var uniqueCategories: [String] {
        let cats = storage.items.map(\.category).filter { $0 != "Uncategorised" }
        return Array(Set(cats)).sorted()
    }

    private var filteredItems: [InventoryItem] {
        var result = storage.items
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.sku.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Back")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.stoqlyPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
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
                
                HStack(spacing: 16) {
                    if teamManager.canEdit {
                        Button(action: { showingEditStorage = true }) {
                            Image(systemName: "pencil")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                    }

                    // Smart Count — AI-powered inventory input
                    Button(action: { showingSmartCount = true }) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.stoqlyPrimary)
                    }
                    .accessibilityLabel("Smart Count")

                    if teamManager.canEdit {
                        Button(action: {
                            if SubscriptionManager.shared.canAddItem(currentItemCount: storage.items.count) {
                                showingAddItem = true
                            } else {
                                showingItemLimitPaywall = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Add Item")
                        .accessibilityIdentifier("addItemButton")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            HStack(spacing: 20) {
                StatCard(title: "Total Items", value: "\(storage.itemCount)", color: .stoqlyPrimary)
                StatCard(title: "Total Value", value: currencyManager.formatPrice(storage.totalValue), color: .stoqlyAccent)
                StatCard(title: "Low Stock", value: "\(viewModel.lowStockCount(for: storage))", color: .stoqlyWarning)
            }
            .padding(.horizontal)
            
            SearchBar(text: $searchText, placeholder: "Search items...")
                .padding(.horizontal)
                .padding(.top, 16)
            if !uniqueCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            color: .stoqlyPrimary,
                            action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedCategory = nil
                            }
                        )
                        ForEach(uniqueCategories, id: \.self) { cat in
                            FilterChip(
                                title: cat,
                                isSelected: selectedCategory == cat,
                                color: .stoqlyPrimary,
                                action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedCategory = cat
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            List {
                if filteredItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.stoqlyPrimary.opacity(0.7))
                        Text("\(storage.name) is empty")
                            .font(.title3).fontWeight(.semibold)
                        Text(
                            searchText.isEmpty
                                ? "Tap + to add your first item here."
                                : "No items match your search."
                        )
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                        if searchText.isEmpty, teamManager.canEdit {
                            Button(action: { showingAddItem = true }) {
                                Label("Add Item", systemImage: "plus.circle.fill")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .accessibilityIdentifier("addItemButton")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredItems, id: \.id) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCard(item: item)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .accessibilityLabel("\(item.name), SKU: \(item.sku)")
                        .accessibilityIdentifier(item.sku.isEmpty ? "itemNavLink_\(item.name)" : "itemNavLink_\(item.sku.replacingOccurrences(of: "-", with: "_"))")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if teamManager.canEdit {
                                Button {
                                    showingQuickCount = item
                                } label: {
                                    Label("Count", systemImage: "list.clipboard.fill")
                                }
                                .tint(.green)
                                .accessibilityIdentifier("swipeCountAction")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if teamManager.canDeleteItem {
                                Button(role: .destructive) {
                                    showingDeleteAlert = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if teamManager.canEdit {
                                Button {
                                    showingEditItem = item
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddItem, onDismiss: {
            // Refresh list after add — SwiftUI List can lag behind insert on iOS 26.
            searchText = ""
            selectedCategory = nil
        }) {
            AddItemView(storage: storage)
                .sheetStyle()
        }
        .sheet(isPresented: $showingEditStorage) {
            EditStorageView(storage: storage)
                .sheetStyle()
        }
        .sheet(item: $showingEditItem) { item in
            EditItemView(item: item)
                .sheetStyle()
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView(source: "item_limit")
                .sheetStyle()
        }
        .sheet(isPresented: $showingSmartCount) {
            SmartCountView(preselectedStorage: storage)
                .sheetStyle()
        }
        .sheet(item: $showingQuickCount, onDismiss: {
            // If user tapped "Advanced options" inside QuickCountView,
            // open the full count screen after the quick sheet fully dismisses.
            if let pending = pendingFullCountItem {
                pendingFullCountItem = nil
                showingFullCount = pending
            }
        }) { item in
            QuickCountView(item: item, onOpenFullCount: {
                pendingFullCountItem = item
            })
            .sheetStyle()
        }
        .sheet(item: $showingFullCount) { item in
            CountItemView(item: item)
                .sheetStyle()
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
                    let name = item.name
                    AnalyticsManager.shared.track(.itemDeleted(category: item.category))
                    FirestoreManager.shared.deleteItem(item)
                    SpotlightManager.shared.deindex(item)
                    modelContext.delete(item)
                    modelContext.safeSave(context: "storageDetail delete item")
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    toastMessage = "\"\(name)\" deleted"
                }
                showingDeleteAlert = nil
            }
        } message: {
            if let item = showingDeleteAlert {
                Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
            }
        }
        .toast(message: $toastMessage)
    }
    
    
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
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
                .fill(item.isOutOfStock ? Color.stoqlyDanger : (item.isLowStock ? Color.stoqlyWarning : Color.stoqlySuccess))
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

                if item.category != "Uncategorised" {
                    Text(item.category)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.currentQuantity.smartFormatted)
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
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var uoms: [UOM]
    @Query(sort: \ItemTemplate.name) private var templates: [ItemTemplate]
    @StateObject private var teamManager = TeamManager.shared

    @State private var showingTemplatePicker = false
    @State private var selectedPhotoData: Data? = nil
    @State private var name = ""
    @State private var description = ""
    @State private var sku = ""
    @State private var barcode = ""
    @State private var currentQuantity = ""
    @State private var minQuantity = ""
    @State private var maxQuantity = ""
    @State private var unitCost = ""
    @State private var selectedUOM: UOM?
    @State private var category = "Uncategorised"
    @State private var hasExpiryDate = false
    @State private var expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var showingBarcodeScanner = false
    /// Stashes the scanned code while the fullScreenCover dismisses; applied
    /// in `onDismiss` so we don't mutate `barcode` in the same render pass
    /// that toggles `showingBarcodeScanner`.
    @State private var pendingScannedBarcode: String?
    @State private var sourceTemplateId: UUID? = nil

    enum Field: Hashable {
        case name, description, sku, barcode
        case currentQuantity, minQuantity, maxQuantity, unitCost
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                ItemPhotoSection(
                    selectedPhotoData: $selectedPhotoData,
                    existingPhotoURL: nil
                )

                if subscriptionManager.isPro && !templates.isEmpty && teamManager.canEdit {
                    Section {
                        Button {
                            showingTemplatePicker = true
                        } label: {
                            Label("Use Template", systemImage: "doc.on.doc.fill")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Section(header: Text("Item Information")) {
                    TextField("Item Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("itemNameField")
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                        .focused($focusedField, equals: .description)
                    TextField("SKU (Optional)", text: $sku)
                        .focused($focusedField, equals: .sku)
                        .accessibilityIdentifier("addItemSkuField")
                    HStack {
                        TextField("Barcode (Optional)", text: $barcode)
                            .focused($focusedField, equals: .barcode)
                        if barcode.isEmpty {
                            Button(action: { showingBarcodeScanner = true }) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title3)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                        }
                    }
                }

                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(InventoryItem.predefinedCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(header: Text("Expiry")) {
                    Toggle("Has Expiry Date", isOn: $hasExpiryDate.animation(.easeInOut(duration: 0.2)))
                    if hasExpiryDate {
                        DatePicker(
                            "Expiry Date",
                            selection: $expiryDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        Text("You'll get a notification 3 days before this item expires.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Quantity & Pricing")) {
                    HStack {
                        Text("Current Quantity")
                            .foregroundColor(.primary)
                        Spacer()
                        TextField("0", text: $currentQuantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .focused($focusedField, equals: .currentQuantity)
                            .accessibilityLabel("Current Quantity")
                            .accessibilityIdentifier("currentQuantityInput")
                    }

                    HStack {
                        HStack(spacing: 4) {
                            Text("Unit of Measure")
                            Text("(UOM)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        Spacer()
                        Picker("", selection: $selectedUOM) {
                            Text("Select UOM").tag(nil as UOM?)
                            ForEach(uoms, id: \.id) { uom in
                                Text("\(uom.name) (\(uom.symbol))").tag(uom as UOM?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                    }

                    TextField("Min Quantity", text: $minQuantity)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .minQuantity)
                        .accessibilityLabel("Min Quantity")
                        .accessibilityIdentifier("minQuantityInput")

                    TextField("Max Quantity", text: $maxQuantity)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .maxQuantity)
                        .accessibilityLabel("Max Quantity")
                        .accessibilityIdentifier("maxQuantityInput")

                    TextField("Unit Cost", text: $unitCost)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .unitCost)
                        .accessibilityIdentifier("unitCostInput")
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
                    Button {
                        saveItem()
                    } label: {
                        Text("Save")
                            .accessibilityIdentifier("addItemSaveButton")
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView(templates: templates) { selected in
                name = selected.name
                description = selected.templateDescription
                category = selected.category
                selectedUOM = uoms.first { $0.symbol == selected.uomSymbol }
                minQuantity = selected.defaultMinQty > 0
                    ? selected.defaultMinQty.smartFormatted : ""
                maxQuantity = selected.defaultMaxQty > 0
                    ? selected.defaultMaxQty.smartFormatted : ""
                sourceTemplateId = selected.id
            }
            .sheetStyle()
        }
        .onAppear {
            if uoms.isEmpty {
                for standardUOM in UOM.standardUOMs {
                    modelContext.insert(standardUOM)
                }
                modelContext.safeSave(context: "initializeStandardUOMs")
            }
            if selectedUOM == nil, let defaultUOM = uoms.first(where: { $0.isDefault }) {
                selectedUOM = defaultUOM
            }
        }
        .onChange(of: uoms.count) { _, _ in
            if selectedUOM == nil, let defaultUOM = uoms.first(where: { $0.isDefault }) {
                selectedUOM = defaultUOM
            }
        }
        // NOTE: must be `.fullScreenCover`, not `.sheet`. Presenting a camera
        // host as a sheet-inside-a-sheet wedges the AVFoundation capture XPC
        // (err=-17281). See the contract comment on BarcodeScannerView.
        // `.sheetStyle()` is intentionally dropped here — its detents only
        // apply to sheets and have no effect on a fullScreenCover.
        //
        // The scanned value is stashed in `pendingScannedBarcode` and applied
        // in `onDismiss` — writing to `barcode` in the same render pass as
        // the dismissal toggle causes SwiftUI to drop the value (or
        // cascade-dismiss the parent sheet) on iOS 16/17.
        .fullScreenCover(
            isPresented: $showingBarcodeScanner,
            onDismiss: {
                if let code = pendingScannedBarcode {
                    barcode = code
                    pendingScannedBarcode = nil
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
    }

    private func resolveUOM() -> UOM? {
        if let selectedUOM { return selectedUOM }
        if let match = uoms.first(where: { $0.isDefault }) ?? uoms.first {
            return match
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<UOM>())) ?? []
        if let match = existing.first(where: { $0.isDefault }) ?? existing.first {
            return match
        }
        for standardUOM in UOM.standardUOMs {
            modelContext.insert(standardUOM)
        }
        modelContext.safeSave(context: "initializeStandardUOMsOnSave")
        let refetched = (try? modelContext.fetch(FetchDescriptor<UOM>())) ?? []
        return refetched.first(where: { $0.isDefault }) ?? refetched.first
    }

    private func saveItem() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let uom = resolveUOM() else { return }

        let item = InventoryItem(
            name: trimmedName,
            description: description,
            sku: sku,
            barcode: barcode,
            currentQuantity: Double(currentQuantity) ?? 0,
            minQuantity: Double(minQuantity) ?? 0,
            maxQuantity: Double(maxQuantity) ?? 0,
            unitCost: Double(unitCost) ?? 0,
            category: category,
            expiryDate: hasExpiryDate ? expiryDate : nil,
            storage: storage,
            uom: uom
        )
        item.createdFromTemplateId = sourceTemplateId
        modelContext.insert(item)

        // If the item was created with an expiry date and non-zero quantity,
        // record the initial stock as a batch so all expiry dates are tracked
        // consistently in the Batches section.
        let initialQty = Double(currentQuantity) ?? 0
        if hasExpiryDate, let expiry = item.expiryDate, initialQty > 0 {
            let initialBatch = InventoryBatch(
                quantity: initialQty,
                expiryDate: expiry,
                notes: "Initial stock",
                item: item
            )
            modelContext.insert(initialBatch)
        }

        modelContext.safeSave(context: "addItemToStorage")

        AnalyticsManager.shared.track(.itemAdded(
            category: item.category,
            hasBarcode: !item.barcode.isEmpty,
            hasPhoto: item.photoURL != nil
        ))

        let event = ActivityEvent(
            eventType: "ItemAdded",
            itemName: name,
            storageName: storage.name,
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "saveNew activity event")
        FirestoreManager.shared.syncActivity(event)

        if let photoData = selectedPhotoData {
            let itemId = item.id
            Task {
                do {
                    let url = try await FirestoreManager.shared.uploadItemPhoto(photoData, itemId: itemId)
                    item.photoURL = url
                    modelContext.safeSave(context: "save photoURL after upload")
                    FirestoreManager.shared.syncItem(item)
                } catch {
                    print("Photo upload failed: \(error.localizedDescription)")
                }
            }
        }

        FirestoreManager.shared.syncItem(item)
        AdManager.shared.recordCompletion(event: .itemAdded)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

struct ItemDetailView: View {
    let item: InventoryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var detailVM = ItemDetailViewModel()
    @StateObject private var teamManager = TeamManager.shared
    @State private var showingCountModal = false
    @State private var showingQuickCount = false
    @State private var showingEditItem = false
    @State private var showingDeleteAlert = false

    /// All activity events, newest first. Filtered to this item's events
    /// via `recentItemEvents`. Using a single global query rather than a
    /// per-item predicate keeps the SwiftData fetch simple — the filter
    /// is in-memory and we only ever take the first 3.
    @Query(sort: \ActivityEvent.occurredAt, order: .reverse)
    private var allActivityEvents: [ActivityEvent]

    // MARK: - Sorted count history (newest first)
    private var sortedHistory: [InventoryCount] {
        item.countHistory.sorted { $0.countDate > $1.countDate }
    }

    /// Last 3 ActivityEvents whose `itemName` matches this item. Matching
    /// by name (rather than id) mirrors how events are recorded across
    /// the codebase and survives item-name changes only going forward.
    private var recentItemEvents: [ActivityEvent] {
        allActivityEvents.filter { $0.itemName == item.name }.prefix(3).map { $0 }
    }

    // MARK: - Status colour helper
    private var statusColor: Color {
        item.isOutOfStock ? .red : item.isLowStock ? .orange : item.isOverStock ? .purple : .green
    }

    // MARK: - Batch display helpers

    /// Lightweight value type used only for rendering the Batches section.
    private struct BatchDisplayItem: Identifiable {
        let id: UUID
        let quantity: Double?
        let expiryDate: Date
        let receivedDate: Date?
        let notes: String
        let isSynthetic: Bool
    }

    /// Merges real `InventoryBatch` records with an optional synthetic row for
    /// `item.expiryDate` (set at creation), then sorts by expiry date (FIFO).
    /// The synthetic row fills the gap for items created before batch tracking
    /// was introduced so all expiry dates always appear in one place.
    private var batchDisplayItems: [BatchDisplayItem] {
        let realBatches = item.batches
        var display: [BatchDisplayItem] = realBatches.map {
            BatchDisplayItem(id: $0.id, quantity: $0.quantity,
                             expiryDate: $0.expiryDate, receivedDate: $0.receivedDate,
                             notes: $0.notes, isSynthetic: false)
        }
        if let storedExpiry = item.expiryDate,
           !realBatches.contains(where: { abs($0.expiryDate.timeIntervalSince(storedExpiry)) < 60 }) {
            display.append(BatchDisplayItem(
                id: UUID(), quantity: nil,
                expiryDate: storedExpiry, receivedDate: item.createdAt,
                notes: "Initial stock", isSynthetic: true))
        }
        return display.sorted { $0.expiryDate < $1.expiryDate }
    }

    var body: some View {
        // No NavigationStack here. ItemDetailView is presented either via
        // NavigationLink (which already provides one) or inside a sheet that
        // wraps it in its own NavigationStack (ItemListView scan-to-find,
        // ExpiryTimelineView, CategoryExplorerView). Adding one here would
        // create double nav bars when pushed.
        ScrollView {
            VStack(spacing: 16) {

                // ── 0. Item photo (only when a URL has been uploaded) ──
                if let urlString = item.photoURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()
                                .cornerRadius(14)
                                .padding(.horizontal)
                        case .failure:
                            EmptyView()
                        case .empty:
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray5))
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .overlay(ProgressView())
                                .padding(.horizontal)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                if !teamManager.canEdit {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                        Text("You have view-only access to this workspace.")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                }

                // ── Batches (shown when batch tracking is active) ──────
                // `batchDisplayItems` merges real InventoryBatch records with
                // a synthetic "Initial stock" row for item.expiryDate when it
                // is not yet represented as a batch. Sorted FIFO (soonest first).
                let sortedDisplay = batchDisplayItems
                if !sortedDisplay.isEmpty {
                    DetailSection(title: "Batches (FIFO order)") {
                        ForEach(Array(sortedDisplay.enumerated()), id: \.1.id) { idx, batchItem in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        if let qty = batchItem.quantity {
                                            Text("\(qty.smartFormatted) \(item.uom?.symbol ?? "units")")
                                                .font(.subheadline).fontWeight(.semibold)
                                        } else {
                                            Text(item.uom?.symbol ?? "units")
                                                .font(.subheadline).fontWeight(.semibold)
                                        }
                                        if idx == 0 {
                                            Text("USE FIRST")
                                                .font(.caption2).fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.stoqlyWarning)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text("Expires \(batchItem.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundColor(batchExpiryColor(batchItem.expiryDate))
                                    if !batchItem.notes.isEmpty {
                                        Text(batchItem.notes)
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if let received = batchItem.receivedDate {
                                    Text("Received \(received.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal)
                }

                // ── 1. Stock status card ────────────────────────────
                stockStatusCard

                // ── 2. Context-aware quick actions ──────────────────
                if teamManager.canEdit {
                    quickActionsRow
                        .padding(.horizontal)
                }

                // ── 3. Item info section ────────────────────────────
                DetailSection(title: "Item Info") {
                    DetailRow(label: "Category",    value: item.category)
                    DetailRow(label: "Description", value: item.itemDescription.isEmpty ? "—" : item.itemDescription)
                    DetailRow(label: "SKU",         value: item.sku)
                        .accessibilityIdentifier("itemDetailSkuLine")
                    DetailRow(label: "Barcode",     value: item.barcode.isEmpty ? "—" : item.barcode)
                }
                .padding(.horizontal)

                // ── 4. Storage & limits section ─────────────────────
                DetailSection(title: "Storage & Limits") {
                    DetailRow(label: "Storage",      value: item.storage?.name ?? "—")
                    DetailRow(label: "UOM",          value: item.uom?.name ?? item.uom?.symbol ?? "—")
                    if item.reorderPercentage > 0 && item.maxQuantity > 0 {
                        DetailRow(
                            label: "Reorder Threshold",
                            value: "\(Int(item.reorderPercentage))% of max (\(item.effectiveMinQuantity.smartFormatted))"
                        )
                    } else {
                        DetailRow(label: "Min Quantity", value: item.minQuantity > 0 ? item.minQuantity.smartFormatted : "—")
                    }
                    DetailRow(label: "Max Quantity", value: item.maxQuantity > 0 ? item.maxQuantity.smartFormatted : "—")
                    if item.unitCost > 0 {
                        DetailRow(label: "Unit Cost", value: "$\(String(format: "%.2f", item.unitCost))")
                    }
                    if item.lastPurchasePrice > 0 {
                        DetailRow(
                            label: "Last Purchase",
                            value: "$\(String(format: "%.2f", item.lastPurchasePrice))"
                        )
                        if item.unitCost > 0 {
                            let variance = item.lastPurchasePrice - item.unitCost
                            let pct = item.unitCost > 0 ? (variance / item.unitCost * 100) : 0
                            if variance > 0 {
                                Label(
                                    "Price up \(String(format: "%.1f", pct))% vs unit cost",
                                    systemImage: "arrow.up.circle"
                                )
                                .foregroundColor(.orange)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if variance < 0 {
                                Label(
                                    "Price down \(String(format: "%.1f", abs(pct)))% vs unit cost",
                                    systemImage: "arrow.down.circle"
                                )
                                .foregroundColor(.green)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    // Only show standalone Expiry row for items with no batches.
                    // When batches exist, all expiry dates appear in the Batches section above.
                    if item.batches.isEmpty, let expiry = item.expiryDate {
                        DetailRow(
                            label: "Expiry",
                            value: expiry.formatted(date: .abbreviated, time: .omitted),
                            valueColor: item.isExpired ? .red : item.isExpiringSoon ? .orange : .primary
                        )
                    }
                }
                .padding(.horizontal)

                // ── 5. Quantity trend chart ─────────────────────────
                CountTrendChart(item: item)
                    .padding(.horizontal)

                // ── 6. Count history section ────────────────────────
                if !sortedHistory.isEmpty {
                    DetailSection(title: "Count History") {
                        ForEach(sortedHistory.prefix(5), id: \.id) { count in
                            CountHistoryRow(count: count, uomSymbol: item.uom?.symbol ?? "")
                        }
                        if sortedHistory.count > 5 {
                            Text("\(sortedHistory.count - 5) older count\(sortedHistory.count - 5 == 1 ? "" : "s") not shown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)
                }

                // ── 7. Recent activity for this item ────────────────
                if !recentItemEvents.isEmpty {
                    DetailSection(title: "Recent Activity") {
                        ForEach(recentItemEvents, id: \.id) { event in
                            ActivityEventRow(event: event)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 80)
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if teamManager.canEdit || teamManager.canDeleteItem {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if teamManager.canEdit {
                            Button { showingEditItem = true } label: {
                                Image(systemName: "pencil")
                            }
                        }
                        if teamManager.canDeleteItem {
                            Button { showingDeleteAlert = true } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.stoqlyDanger)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingQuickCount) {
            QuickCountView(item: item, onOpenFullCount: {
                showingQuickCount = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showingCountModal = true
                }
            })
            .sheetStyle()
        }
        .sheet(isPresented: $showingCountModal) {
            CountItemView(item: item)
                .sheetStyle()
        }
        .sheet(isPresented: $showingEditItem) {
            EditItemView(item: item)
                .sheetStyle()
        }
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                detailVM.delete(item)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
        }
        .onAppear {
            detailVM.bind(modelContext: modelContext)
        }
    }

    // MARK: - Context-aware quick actions

    /// Shows different secondary actions depending on the item's stock status.
    /// The primary "Count Item" button is always present.
    /// The secondary slot changes meaning so the label is never mistaken for a status.
    @ViewBuilder
    private var quickActionsRow: some View {
        if item.isOutOfStock {
            // Out of stock — primary: count (to enter new qty), secondary: receive stock shortcut
            HStack(spacing: 12) {
                Button { showingQuickCount = true } label: {
                    Label("Count Item", systemImage: "list.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("countItemButton")

                Button { showingQuickCount = true } label: {
                    Label("Receive Stock", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.large)
            }

        } else if item.isLowStock {
            // Low stock — primary: count, secondary: mark all gone (destructive, needs confirm)
            HStack(spacing: 12) {
                Button { showingQuickCount = true } label: {
                    Label("Count Item", systemImage: "list.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("countItemButton")

                Button {
                    detailVM.markOutOfStock(for: item)
                } label: {
                    Label("Mark as Empty", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.large)
            }

        } else {
            // Healthy stock — just count, no secondary action needed
            Button { showingQuickCount = true } label: {
                Label("Count Item", systemImage: "list.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("countItemButton")
        }
    }

    // MARK: - Batch helpers

    /// Colour used for a batch's "Expires …" line: red if already past, orange
    /// when the batch is within 7 days of expiring, secondary otherwise.
    private func batchExpiryColor(_ date: Date) -> Color {
        if date < Date() { return .red }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 99
        return days <= 7 ? .orange : .secondary
    }

    // MARK: - Stock status card

    private var stockStatusCard: some View {
        VStack(spacing: 12) {
            // Status badge
            Text(item.stockStatus)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .foregroundColor(statusColor)
                .cornerRadius(8)

            // Big quantity
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(item.currentQuantity.smartFormatted)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text(item.uom?.symbol ?? "units")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Stock level bar (only when max is set)
            if item.maxQuantity > 0 {
                stockLevelBar
            }

            // Value
            if item.unitCost > 0 {
                Text("Total value: $\(String(format: "%.2f", item.totalValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    private var stockLevelBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // Fill
                    let fillFraction = min(item.currentQuantity / item.maxQuantity, 1.0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: geo.size.width * fillFraction, height: 8)

                    // Min-quantity marker
                    if item.minQuantity > 0 && item.minQuantity < item.maxQuantity {
                        let minFraction = item.minQuantity / item.maxQuantity
                        Rectangle()
                            .fill(Color.stoqlyWarning)
                            .frame(width: 2, height: 14)
                            .offset(x: geo.size.width * minFraction - 1, y: -3)
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Text("0")
                Spacer()
                if item.minQuantity > 0 {
                    Text("Min \(item.minQuantity.smartFormatted)")
                        .foregroundColor(.stoqlyWarning)
                }
                Spacer()
                Text("Max \(item.maxQuantity.smartFormatted)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Reusable section wrapper

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 14)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Detail row

struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        Divider().padding(.leading, 0)
    }
}

// MARK: - Count history row

private struct CountHistoryRow: View {
    let count: InventoryCount
    let uomSymbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Variance direction indicator
            Image(systemName: count.variance > 0 ? "arrow.up.circle.fill"
                           : count.variance < 0 ? "arrow.down.circle.fill"
                           : "minus.circle.fill")
                .font(.title3)
                .foregroundColor(count.variance > 0 ? .green : count.variance < 0 ? .red : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count.previousQuantity.smartFormatted) → \(count.countedQuantity.smartFormatted) \(uomSymbol)")
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(count.countDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundColor(.secondary)
                    if !count.adjustmentReason.isEmpty {
                        Text("·")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(count.adjustmentReason)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(count.variance >= 0 ? "+\(count.variance.smartFormatted)" : count.variance.smartFormatted)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(count.variance > 0 ? .green : count.variance < 0 ? .red : .secondary)
        }
        .padding(.vertical, 9)
        Divider()
    }
}

struct CountItemView: View {
    let item: InventoryItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var countVM = CountItemViewModel()
    
    @State private var countedQuantity = ""
    @State private var adjustmentReason = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Current Information")) {
                    HStack {
                        Text("Current Quantity:")
                        Spacer()
                        Text("\(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
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
                    TextField("Counted Quantity", text: $countVM.countedQuantity)
                        .keyboardType(.decimalPad)
                    
                    Picker("Adjustment Reason", selection: $countVM.adjustmentReason) {
                        Text("Select reason").tag("")
                        Text("Physical Count").tag("Physical Count")
                        Text("Damage / Write-off").tag("Damage / Write-off")
                        Text("Theft / Shrinkage").tag("Theft / Shrinkage")
                        Text("Supplier Correction").tag("Supplier Correction")
                        Text("Transfer").tag("Transfer")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    TextField("Notes (Optional)", text: $countVM.notes, axis: .vertical)
                        .lineLimit(3)
                }
                
                if let newQuantity = Double(countVM.countedQuantity) {
                    Section(header: Text("Adjustment Preview")) {
                        HStack {
                            Text("Variance:")
                            Spacer()
                            Text((newQuantity - item.currentQuantity).smartFormatted)
                                .fontWeight(.medium)
                                .foregroundColor(newQuantity > item.currentQuantity ? .green : .red)
                        }
                        
                        HStack {
                            Text("New Quantity:")
                            Spacer()
                            Text("\(newQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
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
                        countVM.saveCount(for: item)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                    .disabled(countVM.countedQuantity.isEmpty || countVM.adjustmentReason.isEmpty)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            countVM.bind(modelContext: modelContext)
        }
    }
}

// MARK: - Quick Count Sheet

struct QuickCountView: View {
    let item: InventoryItem
    /// Called when user wants the full count screen (to change UOM/reason).
    /// The parent dismisses this sheet first, then opens CountItemView.
    let onOpenFullCount: () -> Void

    // MARK: - Count mode

    enum CountMode: String, CaseIterable {
        case setTo     = "Set to"
        case adjustBy  = "Adjust by"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var countVM = CountItemViewModel()
    @FocusState private var quantityFocused: Bool
    @State private var showingLargeChangeAlert = false
    @State private var countMode: CountMode = .setTo
    /// Separate text binding for Adjust-by delta (may be negative, e.g. "-5").
    @State private var deltaText: String = ""
    @State private var showingCalculator: Bool = false
    // ── Batch tracking (only relevant when adding stock) ─────────────────
    @State private var trackAsBatch: Bool = false
    @State private var batchExpiryDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    // ── First-time count tips ─────────────────────────────────────────────
    @AppStorage("stoqly_hasSeenCountTips") private var hasSeenCountTips: Bool = false
    @State private var showingCountTips: Bool = false

    // MARK: - Derived values

    /// The absolute new quantity that will be saved, regardless of mode.
    private var resultingQuantity: Double? {
        switch countMode {
        case .setTo:
            return Double(countVM.countedQuantity)
        case .adjustBy:
            guard let delta = Double(deltaText) else { return nil }
            return max(0, item.currentQuantity + delta)
        }
    }

    private var variance: Double? {
        guard let q = resultingQuantity else { return nil }
        return q - item.currentQuantity
    }

    /// True when the user is COUNTING UP (i.e. receiving new stock) — controls
    /// visibility of the optional "Track as new batch" toggle below.
    private var isAddingStock: Bool {
        guard let q = resultingQuantity else { return false }
        return q > item.currentQuantity
    }

    private var isLargeChange: Bool {
        guard let qty = resultingQuantity, item.currentQuantity > 0 else { return false }
        return abs(qty - item.currentQuantity) / item.currentQuantity > 0.5
    }

    private var canSave: Bool {
        switch countMode {
        case .setTo:    return !countVM.countedQuantity.isEmpty
        case .adjustBy: return !deltaText.isEmpty
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Item header ──────────────────────────────────────
                    VStack(spacing: 6) {
                        Text(item.name)
                            .font(.title3).fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.isOutOfStock ? Color.stoqlyDanger : item.isLowStock ? Color.stoqlyWarning : Color.stoqlySuccess)
                                .frame(width: 8, height: 8)
                            Text("Current: \(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "units")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)

                    // ── Quantity input block ─────────────────────────────
                    VStack(spacing: 14) {

                        // Mode toggle
                        Picker("Count Mode", selection: $countMode) {
                            ForEach(CountMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .onChange(of: countMode) { _, _ in
                            // Reset the inactive field when switching modes
                            // so stale input doesn't bleed across.
                            if countMode == .setTo { deltaText = "" }
                            else { countVM.countedQuantity = "" }
                            // Keep keyboard up
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                quantityFocused = true
                            }
                        }

                        // Stepper row: [−]  BigField  [+]  UOM
                        HStack(alignment: .center, spacing: 16) {

                            // Minus button
                            Button {
                                stepValue(by: -1)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(Color(.systemGray3))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .accessibilityLabel("Decrease by 1")

                            // Big number field
                            ZStack {
                                let activeText = countMode == .setTo ? countVM.countedQuantity : deltaText
                                if activeText.isEmpty {
                                    Text(countMode == .adjustBy ? "0" : "--")
                                        .font(.system(size: 52, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(.systemGray3))
                                        .allowsHitTesting(false)
                                }
                                if countMode == .setTo {
                                    TextField("", text: $countVM.countedQuantity)
                                        .font(.system(size: 52, weight: .bold, design: .rounded))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .focused($quantityFocused)
                                        .frame(maxWidth: 160)
                                        .accessibilityLabel("New Quantity")
                                        .accessibilityIdentifier("quickCountQuantityInput")
                                } else {
                                    TextField("", text: $deltaText)
                                        .font(.system(size: 52, weight: .bold, design: .rounded))
                                        // numbersAndPunctuation lets user type a minus sign
                                        .keyboardType(.numbersAndPunctuation)
                                        .multilineTextAlignment(.center)
                                        .focused($quantityFocused)
                                        .frame(maxWidth: 160)
                                        .accessibilityLabel("Adjustment Amount")
                                }
                            }

                            // Plus button
                            Button {
                                stepValue(by: 1)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.stoqlyPrimary)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .accessibilityLabel("Increase by 1")
                        }
                        .padding(.horizontal, 8)

                        // UOM label + calculator button on same row
                        HStack(spacing: 10) {
                            Text(item.uom?.symbol ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button {
                                showingCalculator = true
                            } label: {
                                Label("Calculator", systemImage: "calculator")
                                    .font(.caption)
                                    .foregroundColor(.stoqlyPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.stoqlyPrimary.opacity(0.1))
                                    .cornerRadius(10)
                            }
                        }

                        // Live feedback pill
                        if let v = variance {
                            Group {
                                if countMode == .setTo {
                                    // Shows delta from current
                                    Text(v == 0 ? "No change" : "\(v > 0 ? "+" : "")\(v.smartFormatted) from current")
                                } else {
                                    // Shows resulting absolute quantity
                                    if let result = resultingQuantity {
                                        Text(v == 0
                                             ? "No change (stays \(item.currentQuantity.smartFormatted))"
                                             : "\(item.currentQuantity.smartFormatted) → \(result.smartFormatted) \(item.uom?.symbol ?? "")")
                                    }
                                }
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                v == 0 ? Color(.systemGray5) :
                                v > 0 ? Color.stoqlySuccess.opacity(0.15) :
                                Color.stoqlyDanger.opacity(0.15)
                            )
                            .foregroundColor(v == 0 ? .secondary : v > 0 ? .green : .red)
                            .cornerRadius(20)
                            .animation(.easeInOut(duration: 0.2), value: v)
                        }

                        // Hint for adjust mode
                        if countMode == .adjustBy {
                            Text("Negative values reduce stock")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }

                        Spacer().frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // ── Notes ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Add a note about this count…", text: $countVM.notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .accessibilityLabel("Notes")
                    }
                    .padding(.horizontal)

                    // ── Batch tracking (only when receiving / adding stock) ──
                    if isAddingStock {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Track as new batch", isOn: $trackAsBatch.animation(.easeInOut(duration: 0.2)))
                                .font(.subheadline)
                                .padding(.horizontal, 16)

                            if trackAsBatch {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Batch expiry date")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                    DatePicker(
                                        "",
                                        selection: $batchExpiryDate,
                                        in: Date()...,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .padding(.horizontal, 16)
                                    Text("You'll be reminded 3 days before this batch expires.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    }

                    // ── Advanced link ─────────────────────────────────────
                    Button(action: {
                        onOpenFullCount()
                        dismiss()
                    }) {
                        Label("Change UOM or count type", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .foregroundColor(.stoqlyPrimary)
                    }

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Quick Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if isLargeChange {
                            showingLargeChangeAlert = true
                        } else {
                            performSave()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            countVM.bind(modelContext: modelContext)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                quantityFocused = true
            }
            if !hasSeenCountTips {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showingCountTips = true
                }
            }
        }
        .alert("Large Change Detected", isPresented: $showingLargeChangeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Save Anyway", role: .destructive) {
                performSave()
            }
        } message: {
            if let qty = resultingQuantity {
                let current = item.currentQuantity.smartFormatted
                let entered = qty.smartFormatted
                let uom = item.uom?.symbol ?? "units"
                Text("Changing \(item.name) from \(current) to \(entered) \(uom). Double-check before saving.")
            }
        }
        .sheet(isPresented: $showingCalculator) {
            CalculatorView { result in
                // Drop calculator result into whichever field is active
                let formatted = result.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", result)
                    : String(format: "%.4f", result)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                switch countMode {
                case .setTo:    countVM.countedQuantity = formatted
                case .adjustBy: deltaText = formatted
                }
            }
            .sheetStyle()
        }
        .sheet(isPresented: $showingCountTips) {
            CountFirstTimeTipsView {
                hasSeenCountTips = true
                showingCountTips = false
            }
            .sheetStyle()
        }
    }

    // MARK: - Helpers

    /// Adjusts the active field value by `amount` (±1), clamping Set-to mode to ≥ 0.
    private func stepValue(by amount: Double) {
        switch countMode {
        case .setTo:
            let current = Double(countVM.countedQuantity) ?? item.currentQuantity
            let newVal  = max(0, current + amount)
            countVM.countedQuantity = formatStepResult(newVal)
        case .adjustBy:
            let current = Double(deltaText) ?? 0
            deltaText   = formatStepResult(current + amount)
        }
    }

    /// Formats a stepper result: integer if whole, two decimals otherwise.
    private func formatStepResult(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }

    /// Finalises `countVM.countedQuantity` from whichever mode is active, then saves.
    private func performSave() {
        // Capture the previous quantity BEFORE saveCount runs — `saveCount`
        // updates `item.currentQuantity` in place, so any post-save reference
        // to it would always equal the new value.
        let previousQty = item.currentQuantity
        let plannedQty  = resultingQuantity

        switch countMode {
        case .setTo:
            countVM.adjustmentReason = "Physical Count"
        case .adjustBy:
            let delta  = Double(deltaText) ?? 0
            let newQty = max(0, item.currentQuantity + delta)
            countVM.countedQuantity  = formatStepResult(newQty)
            countVM.adjustmentReason = delta >= 0 ? "Stock Received" : "Stock Adjustment"
        }
        countVM.saveCount(for: item)

        // Create a batch record only when the user opted in AND stock went up.
        if trackAsBatch, let qty = plannedQty, qty > previousQty {
            let addedQty = qty - previousQty
            let batch = InventoryBatch(
                quantity: addedQty,
                expiryDate: batchExpiryDate,
                notes: countVM.notes,
                item: item
            )
            modelContext.insert(batch)
            modelContext.safeSave(context: "QuickCountView createBatch")
        }

        dismiss()
    }
}

// MARK: - CountFirstTimeTipsView

/// Shown the first time a user opens QuickCountView. Teaches batch/FIFO, par levels,
/// and Adjust-by mode. Dismissed via the "Got it" button which sets the AppStorage flag.
struct CountFirstTimeTipsView: View {

    let onDismiss: () -> Void

    private struct CountTip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }

    private let tips: [CountTip] = [
        CountTip(
            icon: "clock.badge.checkmark",
            title: "FIFO Batch Tracking",
            description: "When counting stock UP, toggle \"Track as new batch\" to log the expiry date. Stoqly tracks batches in FIFO order — oldest stock is always used first, so nothing expires unnoticed."
        ),
        CountTip(
            icon: "chart.bar.xaxis",
            title: "Par Levels (Min/Max Qty)",
            description: "Set a Min Quantity on each item (via its Edit screen) and Stoqly will alert you when stock falls below it. This is your reorder trigger. Max Qty flags overstock so you don't over-purchase."
        ),
        CountTip(
            icon: "plusminus",
            title: "Adjust By Mode",
            description: "Switch to \"Adjust by\" to log a delivery (+10 boxes) or correct usage (-3 kg) without needing to know the total current count. Perfect for quick updates mid-shift."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("Quick Count Tips")
                        .font(.title3).fontWeight(.bold)
                    Text("A few things that'll save you time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal)

            Divider()

            // ── Tip cards ─────────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: tip.icon)
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                                .frame(width: 32)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.title)
                                    .font(.headline)
                                Text(tip.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }

            Divider()

            // ── Dismiss button ────────────────────────────────────────────
            Button(action: onDismiss) {
                Text("Got it")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.stoqlyPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
            .accessibilityIdentifier("countTipsDismissButton")
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    let storage = Storage(name: "Sample Storage", location: "Warehouse A", description: "Sample description")
    return StorageDetailView(storage: storage)
        .environmentObject(CurrencyManager())
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 