import SwiftUI
import SwiftData
import UIKit

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    @StateObject private var viewModel = ItemListViewModel()
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var teamManager = TeamManager.shared
    @State private var showingAddItem = false
    @State private var showingExport = false
    @State private var showingSmartCount = false
    @State private var showingEditItem: InventoryItem?
    @State private var showingDeleteAlert: InventoryItem?
    @State private var showingQuickCount: InventoryItem? = nil
    @State private var showingFullCount: InventoryItem? = nil
    @State private var pendingFullCountItem: InventoryItem? = nil
    @State private var showingScanToFind = false
    @State private var scanToFindResult: InventoryItem? = nil
    /// Bridges the scanned code across the fullScreenCover dismissal. The
    /// look-up (found-vs-not-found) happens in the cover's `onDismiss` so the
    /// follow-up sheet only opens once the scanner has fully gone away —
    /// otherwise SwiftUI drops the next presentation.
    @State private var pendingScanResult: String? = nil
    /// Triggers `AddItemToStorageView` pre-filled with the scanned barcode
    /// when no existing item matches. Wrapped in a per-scan `UUID` so the
    /// sheet re-presents even if the user scans the same not-found barcode
    /// twice in a row.
    @State private var scannedBarcodeToAdd: ScannedBarcodePrefill? = nil
    /// Bottom toast confirming a destructive action (item deletion). Auto-clears
    /// after ~2 seconds via the `.toast(message:)` view modifier.
    @State private var toastMessage: String? = nil
    @State private var selectedSpotlightItem: InventoryItem? = nil

    /// Identifiable wrapper for the "scanned barcode that didn't match any
    /// existing item" sheet. A fresh `id` per scan guarantees `.sheet(item:)`
    /// re-fires even on repeat scans of the same code.
    private struct ScannedBarcodePrefill: Identifiable {
        let id = UUID()
        let code: String
    }

    private var uniqueCategories: [String] {
        Array(Set(items.map(\.category))).sorted()
    }

    var body: some View {
        NavigationStack {
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
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Export Data")

                        Button(action: { showingScanToFind = true }) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Scan to Find Item")

                        Button(action: { showingSmartCount = true }) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Smart Count")
                        
                        if teamManager.canEdit {
                            Button(action: { showingAddItem = true }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                            .accessibilityLabel("Add Item")
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
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 140)
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
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: 140)
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

                    if !uniqueCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                FilterChip(
                                    title: "All",
                                    isSelected: viewModel.selectedCategory == nil,
                                    color: .blue,
                                    action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        viewModel.setSelectedCategory(nil)
                                    }
                                )
                                ForEach(uniqueCategories, id: \.self) { cat in
                                    FilterChip(
                                        title: cat,
                                        isSelected: viewModel.selectedCategory == cat,
                                        color: .blue,
                                        action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            viewModel.setSelectedCategory(cat)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    SearchBar(text: $viewModel.searchText, placeholder: "Search items...")
                        .onChange(of: viewModel.searchText) { _, newValue in
                            viewModel.setSearchText(newValue)
                        }
                        .padding(.horizontal)
                }
                List {
                    if viewModel.filteredItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "cube.box.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.blue.opacity(0.8))
                            Text("No items yet")
                                .font(.title3).fontWeight(.semibold)
                            Text(
                                viewModel.searchText.isEmpty && viewModel.selectedCategory == nil
                                    ? "Add your first item using the + button above,\nor tap into a storage to add items there."
                                    : "Try a different name, category, or barcode."
                            )
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                            if viewModel.searchText.isEmpty && viewModel.selectedCategory == nil,
                               teamManager.canEdit {
                                Button(action: { showingAddItem = true }) {
                                    Label("Add Item", systemImage: "plus.circle.fill")
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.filteredItems.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemRowView(item: item)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemToStorageView()
                .sheetStyle()
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
                .sheetStyle()
        }
        .sheet(isPresented: $showingSmartCount) {
            SmartCountView().sheetStyle()
        }
        .sheet(item: $showingEditItem) { item in
            EditItemView(item: item)
                .sheetStyle()
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
            .sheetStyle()
        }
        .sheet(item: $showingFullCount) { item in
            CountItemView(item: item)
                .sheetStyle()
        }
        // "Scan to Find" — looks up the scanned code in the existing items.
        //   Match found       → presents ItemDetailView (existing behaviour).
        //   No match          → presents AddItemToStorageView pre-filled with
        //                       the scanned barcode, so the user can add it
        //                       on the spot.
        //
        // The lookup runs in `onDismiss` (not in `onScan`) so the next sheet
        // is presented AFTER the fullScreenCover has fully torn down —
        // otherwise SwiftUI drops the second presentation on iOS 16/17.
        .fullScreenCover(
            isPresented: $showingScanToFind,
            onDismiss: {
                guard let code = pendingScanResult else { return }
                pendingScanResult = nil
                let found = items.first(where: { $0.barcode == code && !$0.barcode.isEmpty }) != nil
                AnalyticsManager.shared.track(.barcodeScanResult(found: found, enriched: false))
                if let foundItem = items.first(where: { $0.barcode == code && !$0.barcode.isEmpty }) {
                    scanToFindResult = foundItem
                } else {
                    scannedBarcodeToAdd = ScannedBarcodePrefill(code: code)
                }
            }
        ) {
            BarcodeScannerView(
                onScan: { code, _ in
                    pendingScanResult = code
                    showingScanToFind = false
                },
                onCancel: {
                    pendingScanResult = nil
                    showingScanToFind = false
                }
            )
            .onAppear {
                AnalyticsManager.shared.track(.barcodeScanInitiated)
            }
        }
        .sheet(item: $scanToFindResult) { item in
            // ItemDetailView no longer provides its own NavigationStack
            // (B6 fix). Wrap it here so the toolbar / nav title still render
            // when presented as a sheet.
            NavigationStack {
                ItemDetailView(item: item)
            }
            .sheetStyle()
        }
        .sheet(item: $scannedBarcodeToAdd) { prefill in
            AddItemToStorageView(initialBarcode: prefill.code)
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
                    viewModel.deleteItem(item)
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
        .onAppear {
            viewModel.bind(modelContext: modelContext, items: items, storages: storages)
        }
        .onChange(of: items) { _, newItems in
            viewModel.updateItems(newItems)
        }
        .onChange(of: storages) { _, newStorages in
            viewModel.updateStorages(newStorages)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotlightItemSelected)) { note in
            guard let idString = note.userInfo?["itemID"] as? String,
                  let uuid = UUID(uuidString: idString),
                  let item = items.first(where: { $0.id == uuid }) else { return }
            selectedSpotlightItem = item
        }
        .sheet(item: $selectedSpotlightItem) { item in
            NavigationStack {
                ItemDetailView(item: item)
            }
            .sheetStyle()
        }
        .toast(message: $toastMessage)
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
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct AddItemToStorageView: View {
    /// Optional barcode to pre-fill on appear — used by the "Scan to Find"
    /// flow in ItemListView when the scanned code matches no existing item.
    /// Defaults to `""` so the existing zero-arg call sites still compile.
    let initialBarcode: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    @Query(sort: \ItemTemplate.name) private var templates: [ItemTemplate]
    @StateObject private var formVM = ItemFormViewModel()
    @StateObject private var teamManager = TeamManager.shared
    @State private var showingTemplatePicker = false
    @State private var showingItemLimitPaywall = false
    @State private var showingBarcodeScanner = false
    /// Stores the scanned code while the fullScreenCover dismisses; applied
    /// in `onDismiss` so we don't mutate `formVM.barcode` in the same render
    /// pass that toggles `showingBarcodeScanner` (which causes SwiftUI to
    /// drop the value or cascade-dismiss the parent sheet).
    @State private var pendingScannedBarcode: String?

    init(initialBarcode: String = "") {
        self.initialBarcode = initialBarcode
    }

    private var selectedStorageItemCount: Int {
        formVM.selectedStorage?.items.count ?? 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                    TextField("Item Name", text: $formVM.name)
                        .accessibilityIdentifier("itemNameField")
                    TextField("Description (Optional)", text: $formVM.description, axis: .vertical)
                        .lineLimit(3)
                    TextField("SKU (Optional)", text: $formVM.sku)
                        .accessibilityIdentifier("addItemSkuField")
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
                
                Section(header: Text("Quantity & Pricing")) {
                    TextField("Current Quantity", text: $formVM.currentQuantity)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("currentQuantityInput")
                    
                    TextField("Min Quantity", text: $formVM.minQuantity)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("minQuantityInput")
                    
                    TextField("Max Quantity", text: $formVM.maxQuantity)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("maxQuantityInput")
                    
                    TextField("Unit Cost", text: $formVM.unitCost)
                        .keyboardType(.decimalPad)
                }
            }
            // IMPORTANT: the scanner's `.fullScreenCover` MUST be attached
            // INSIDE the NavigationStack (here, on the Form), not as a sibling
            // of `.sheet(isPresented: $showingItemLimitPaywall)` below. With
            // two presentation modifiers (a `.sheet` + a `.fullScreenCover`)
            // at the same level on this view, iOS 16/17 routes the cover's
            // dismissal up through the parent `showingAddItem` sheet, which
            // tears down `formVM` and `pendingScannedBarcode` before the
            // cover's `onDismiss` can apply the scanned value. Attaching the
            // cover here isolates it from the paywall sheet entirely.
            //
            // Same XPC contract still applies — must be `.fullScreenCover`,
            // not `.sheet`. See BarcodeScannerView.
            //
            // The scanned value is stashed in `pendingScannedBarcode` and
            // applied in `onDismiss` — writing to `formVM.barcode` in the
            // same render pass as the dismissal toggle causes SwiftUI to
            // drop the value on iOS 16/17.
            .fullScreenCover(
                isPresented: $showingBarcodeScanner,
                onDismiss: {
                    if let code = pendingScannedBarcode {
                        formVM.barcode = code
                        pendingScannedBarcode = nil
                        // Phase 3 — kick off smart enrichment lookup. Gated on
                        // `isPro` inside `enrichFromBarcode`, so free users
                        // get no network call. Fire-and-forget — never blocks
                        // the UI.
                        Task {
                            await formVM.enrichFromBarcode(code, uoms: uoms)
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
                        if SubscriptionManager.shared.canAddItem(currentItemCount: selectedStorageItemCount) {
                            formVM.saveNew()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } else {
                            showingItemLimitPaywall = true
                        }
                    } label: {
                        Text("Save")
                            .accessibilityIdentifier("addItemSaveButton")
                    }
                }
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView(templates: templates) { selected in
                formVM.name = selected.name
                formVM.description = selected.templateDescription
                formVM.category = selected.category
                formVM.selectedUOM = uoms.first { $0.symbol == selected.uomSymbol }
                formVM.minQuantity = selected.defaultMinQty > 0
                    ? selected.defaultMinQty.smartFormatted : ""
                formVM.maxQuantity = selected.defaultMaxQty > 0
                    ? selected.defaultMaxQty.smartFormatted : ""
                formVM.sourceTemplateId = selected.id
            }
            .sheetStyle()
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView(source: "item_limit")
                .sheetStyle()
        }
        .onAppear {
            formVM.bind(modelContext: modelContext)
            if uoms.isEmpty {
                for standardUOM in UOM.standardUOMs {
                    modelContext.insert(standardUOM)
                }
                modelContext.safeSave(context: "initializeStandardUOMs")
            }
            if formVM.selectedUOM == nil, let defaultUOM = uoms.first(where: { $0.isDefault }) {
                formVM.selectedUOM = defaultUOM
            }
            // Pre-fill the scanned barcode if we were presented from the
            // "Scan to Find → not found" flow. Guarded by `barcode.isEmpty`
            // so reopening the view (e.g. user dismisses the keyboard and
            // .onAppear re-fires) never clobbers a value the user has
            // typed/scanned manually.
            if formVM.barcode.isEmpty && !initialBarcode.isEmpty {
                formVM.barcode = initialBarcode
            }
            // Phase 3 addendum — same enrichment as the in-form scanner path,
            // for barcodes pre-filled via `initialBarcode`. Pro-gated inside
            // `enrichFromBarcode`; free users get no network call / no banner.
            if !formVM.barcode.isEmpty {
                Task {
                    await formVM.enrichFromBarcode(formVM.barcode, uoms: uoms)
                }
            }
        }
        .onChange(of: uoms.count) { _, _ in
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