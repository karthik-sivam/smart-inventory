import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ImageInventoryView
//
// Flow:
//   1. User takes photo or picks from library
//   2. Image compressed and sent to Claude vision
//   3. Claude returns ALL products visible — single item OR whole shelf scan
//   4. Review screen:
//        • Single product → editable form (qty pre-filled, existing-item match check)
//        • Multiple products → editable list, identical to Voice Inventory review
//   5. Save — updates existing item counts or adds new items
//
// Free limit: 3 uses per calendar month. Pro = unlimited.

struct ImageInventoryView: View {
    var preselectedStorage: Storage? = nil
    var onComplete: ((Int) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]

    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    enum Step { case capture, analysing, review, saving }
    @State private var step: Step = .capture

    // Photo capture
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false

    // Multi-product results (shelf scan — any count including 1)
    @State private var parsedItems: [EditableItem] = []

    // Single-product form fields (used when exactly 1 product found)
    @State private var parsedItem: ParsedInventoryItem?
    @State private var matchedExistingItem: InventoryItem?
    @State private var editableName       = ""
    @State private var editableQty        = ""
    @State private var editableUnit       = ""
    @State private var editableCategory   = "Uncategorised"
    @State private var selectedStorage: Storage?

    @State private var errorMessage: String?
    @State private var showingPaywall = false
    @State private var showingItemLimitPaywall = false
    @State private var fluidMode = false
    @State private var editableFillPercent: Double?
    @State private var editableRemainingVolume: String?

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    private var remainingItemSlots: Int {
        ItemCapReview.remainingSlots(
            storage: selectedStorage,
            context: modelContext,
            isPro: subscriptionManager.isPro
        )
    }

    private var canSaveShelfItems: Bool {
        isStorageSelected && ItemCapReview.canSave(
            items: parsedItems,
            remainingSlots: remainingItemSlots,
            isPro: subscriptionManager.isPro
        )
    }

    private var canSaveSingleItem: Bool {
        let nameOk = !editableName.trimmingCharacters(in: .whitespaces).isEmpty
        guard nameOk, isStorageSelected else { return false }
        if subscriptionManager.isPro || matchedExistingItem != nil { return true }
        return remainingItemSlots > 0
    }

    /// Shelf-scan mode: AI returned more than one distinct product type.
    private var isShelfScan: Bool { parsedItems.count > 1 }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .capture:   captureView
                case .analysing: analysingView
                case .review:    reviewView
                case .saving:    savingView
                }
            }
            .navigationTitle("Photo Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let img = newImage else { return }
            Task { await analyseImage(img) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await analyseImage(img)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "ai_limit").sheetStyle()
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView(source: "item_limit", trigger: "item_cap_bulk").sheetStyle()
        }
        .onAppear {
            if selectedStorage == nil, let preselectedStorage {
                selectedStorage = preselectedStorage
            }
        }
        .onChange(of: selectedStorage?.id) { _, _ in
            guard step == .review else { return }
            parsedItems.applyNameMatching(in: selectedStorage)
            parsedItems.applyDefaultCapSelection(
                remainingSlots: remainingItemSlots,
                isPro: subscriptionManager.isPro
            )
            if parsedItems.count == 1, let name = parsedItems.first?.name, let storage = selectedStorage {
                matchedExistingItem = storage.items.first {
                    $0.name.lowercased().contains(name.lowercased()) ||
                    name.lowercased().contains($0.name.lowercased())
                }
            }
        }
    }

    // MARK: - Step 1: Capture

    private var captureView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Usage badge
                if !subscriptionManager.isPro {
                    let remaining = usageManager.remaining(.image, isPro: false)
                    HStack(spacing: 8) {
                        Image(systemName: "camera.badge.plus")
                            .foregroundColor(.stoqlyPrimary)
                        Text(
                            String(
                                format: L("ai.image.quotaRemaining", "%1$d photo scan%2$@ left this month"),
                                remaining,
                                remaining == 1 ? "" : "s"
                            )
                        )
                            .font(.subheadline)
                        Spacer()
                        Button("Go Pro") { showingPaywall = true }
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.stoqlyPrimary)
                    }
                    .padding(12)
                    .background(Color.stoqlyPrimaryTint)
                    .cornerRadius(10)
                }

                storagePickerSection

                Toggle(isOn: $fluidMode) {
                    Label("Measuring fluid level", systemImage: "drop.fill")
                        .font(.subheadline)
                }
                .tint(.stoqlyPrimary)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Works for single items and full shelves", systemImage: "lightbulb")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.stoqlyAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        tipRow("Point at one product — AI identifies it and counts visible units")
                        tipRow("Photograph a whole shelf — AI lists every product found")
                        tipRow("Packaging, labels, and barcodes all work")
                    }
                }
                .padding(12)
                .background(Color.stoqlyAccentTint)
                .cornerRadius(10)

                VStack(spacing: 14) {
                    Button {
                        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
                            showingPaywall = true
                            return
                        }
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .stoqlyButtonStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(!isStorageSelected)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.stoqlyPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(AppTheme.radiusMd)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
                            showingPaywall = true
                            return
                        }
                    })
                    .disabled(!isStorageSelected)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.stoqlyDanger)
                        .padding(10)
                        .background(Color.stoqlyDangerTint)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    // MARK: - Step 2: Analysing

    private var analysingView: some View {
        VStack(spacing: 20) {
            Spacer()
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(AppTheme.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .stroke(Color.stoqlyPrimary.opacity(0.3), lineWidth: 2)
                    )
                    .padding(.horizontal)
            }
            ProgressView()
                .scaleEffect(1.3)
                .tint(.stoqlyPrimary)
            Text("Scanning for products…")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Step 3: Review

    @ViewBuilder
    private var reviewView: some View {
        if isShelfScan {
            shelfScanReviewView
        } else {
            singleItemReviewView
        }
    }

    // ── Single product ──────────────────────────────────────────────────────

    private var singleItemReviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photo thumbnail + match status
                if let image = capturedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(AppTheme.radiusMd)
                            .clipped()

                        VStack(alignment: .leading, spacing: 4) {
                            if let existing = matchedExistingItem {
                                Label("Matched to existing item", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundColor(.stoqlySuccess)
                                Text(
                                    String(
                                        format: L("image.currentStock", "Current stock: %1$@ %2$@"),
                                        existing.currentQuantity.smartFormatted,
                                        existing.uom?.symbol ?? ""
                                    )
                                )
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Label("New item detected", systemImage: "plus.circle.fill")
                                    .font(.caption).foregroundColor(.stoqlyPrimary)
                                Text("Will be added to your inventory")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.stoqlyCard)
                    .cornerRadius(AppTheme.radiusMd)
                }

                VStack(spacing: 16) {
                    formField(label: "Product Name") {
                        TextField("Enter name", text: $editableName)
                    }

                    HStack(spacing: 12) {
                        formField(label: "Quantity") {
                            TextField("0", text: $editableQty)
                                .keyboardType(.decimalPad)
                        }
                        formField(label: "Unit") {
                            TextField("pcs", text: $editableUnit)
                        }
                    }

                    fluidInfoView(fillPercent: editableFillPercent, remainingVolume: editableRemainingVolume, unit: editableUnit)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        Picker("Category", selection: $editableCategory) {
                            ForEach(InventoryItem.predefinedCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.stoqlyPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.stoqlyCard)
                        .cornerRadius(AppTheme.radiusMd)
                    }

                    storagePickerSection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption).foregroundColor(.stoqlyDanger)
                }

                if !subscriptionManager.isPro, matchedExistingItem == nil, remainingItemSlots == 0 {
                    ItemCapOverflowBanner(remainingSlots: 0) {
                        showingItemLimitPaywall = true
                    }
                    .padding(.horizontal, 0)
                }

                HStack(spacing: 12) {
                    Button("Try Again") { resetCapture() }
                        .font(.subheadline)
                        .foregroundColor(.stoqlyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.stoqlyPrimaryTint)
                        .cornerRadius(AppTheme.radiusMd)

                    Button(matchedExistingItem != nil ? "Update Count" : "Add to Inventory") {
                        Task { await saveSingleItem() }
                    }
                    .stoqlyButtonStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(!canSaveSingleItem)
                }
            }
            .padding()
        }
    }

    // ── Shelf scan (multiple products) ──────────────────────────────────────

    private var shelfScanReviewView: some View {
        VStack(spacing: 0) {
            if parsedItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No products detected")
                        .font(.title3).fontWeight(.semibold)
                    Text("Try a clearer photo or move closer to the shelf.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { resetCapture() }
                        .stoqlyButtonStyle()
                    Spacer()
                }
                .padding()
            } else {
                List {
                    Section {
                        storagePickerSection
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    if ItemCapReview.shouldShowBanner(
                        newCount: ItemCapReview.newCount(parsedItems),
                        remainingSlots: remainingItemSlots,
                        isPro: subscriptionManager.isPro
                    ) {
                        Section {
                            ItemCapOverflowBanner(remainingSlots: remainingItemSlots) {
                                showingItemLimitPaywall = true
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        ForEach($parsedItems) { $item in
                            EditableItemRow(
                                item: $item,
                                selectedStorage: selectedStorage,
                                isPro: subscriptionManager.isPro,
                                remainingSlots: remainingItemSlots
                            )
                        }
                        .onDelete { parsedItems.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text(
                                String(
                                    format: L("image.productsFound", "%1$d product%2$@ found"),
                                    parsedItems.count,
                                    parsedItems.count == 1 ? "" : "s"
                                )
                            )
                            Spacer()
                            Text("Swipe to remove")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                VStack(spacing: 12) {
                    Divider()
                    if !subscriptionManager.isPro {
                        ItemCapSelectionCounter(
                            selectedNew: ItemCapReview.selectedNewCount(parsedItems),
                            remainingSlots: remainingItemSlots
                        )
                    }
                    HStack(spacing: 12) {
                        Button("Re-take") { resetCapture() }
                            .font(.subheadline)
                            .foregroundColor(.stoqlyPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(AppTheme.radiusMd)

                        Button(
                            String(
                                format: L("image.saveAll", "Save All (%1$d)"),
                                parsedItems.count
                            )
                        ) {
                            Task { await saveAllItems() }
                        }
                        .stoqlyButtonStyle()
                        .frame(maxWidth: .infinity)
                        .disabled(!canSaveShelfItems)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Step 4: Saving

    private var savingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.stoqlySuccess)
            Text("Saving items…")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Shared sub-views

    private var storagePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage area")
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            Picker("Storage", selection: $selectedStorage) {
                Text("Select storage").tag(Optional<Storage>.none)
                ForEach(storages) { s in
                    Text(s.name).tag(Optional(s))
                }
            }
            .pickerStyle(.menu)
            .tint(.stoqlyPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.stoqlyCard)
            .cornerRadius(AppTheme.radiusMd)
            if !storages.isEmpty && selectedStorage == nil {
                Text("Select a storage to enable photo inventory.")
                    .font(.caption)
                    .foregroundColor(.stoqlyWarning)
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.stoqlyAccent)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formField<Content: View>(label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            content()
                .padding(10)
                .background(Color.stoqlyCard)
                .cornerRadius(AppTheme.radiusMd)
        }
    }

    private func resetCapture() {
        capturedImage = nil
        parsedItem = nil
        parsedItems = []
        matchedExistingItem = nil
        editableFillPercent = nil
        editableRemainingVolume = nil
        step = .capture
    }

    @ViewBuilder
    private func fluidInfoView(fillPercent: Double?, remainingVolume: String?, unit: String) -> some View {
        if let fill = fillPercent {
            Text(
                String(
                    format: L("image.fluidFillLevel", "~%1$d%% full%2$@"),
                    Int(fill),
                    remainingVolume.map { " · \($0)" } ?? ""
                )
            )
                .font(.caption)
                .foregroundColor(.secondary)
        } else if fluidMode && Self.isLiquidUnit(unit) {
            Text("Fill level not visible — enter quantity manually")
                .font(.caption).foregroundColor(.orange)
        }
    }

    private static func isLiquidUnit(_ unit: String) -> Bool {
        let u = unit.lowercased()
        if u == "ml" || u.contains("ml") || u.contains("மில") { return true }
        if u == "l" || u.contains("litre") || u.contains("liter") || u.contains("லி") { return true }
        return false
    }

    // MARK: - Logic: Analyse

    private func analyseImage(_ image: UIImage) async {
        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
            await MainActor.run { showingPaywall = true }
            return
        }

        await MainActor.run {
            capturedImage = image
            step = .analysing
            errorMessage = nil
        }

        let compressed = image.jpegData(compressionQuality: 0.7) ?? Data()

        do {
            let items = try await AIInventoryService.shared.identifyProduct(
                imageData: compressed,
                fluidMode: fluidMode,
                appLanguageCode: LocalizationManager.shared.currentCode
            )
            usageManager.recordUse(.image)

            let storage = selectedStorage

            await MainActor.run {
                // Populate multi-product list (shelf scan path)
                parsedItems = items.map { EditableItem(from: $0) }
                parsedItems.applyNameMatching(in: storage)
                parsedItems.applyDefaultCapSelection(
                    remainingSlots: ItemCapReview.remainingSlots(
                        storage: storage,
                        context: modelContext,
                        isPro: subscriptionManager.isPro
                    ),
                    isPro: subscriptionManager.isPro
                )

                // Also set single-product form fields for the 1-item path
                let parsed = items.first
                parsedItem = parsed
                editableName     = parsed?.name ?? ""
                // Pre-fill quantity from what AI counted — user can adjust before saving
                editableQty      = {
                    guard let qty = parsed?.quantity, qty > 0 else { return "" }
                    return qty == qty.rounded() ? String(Int(qty)) : String(qty)
                }()
                editableUnit     = parsed?.unitSymbol ?? "pcs"
                editableCategory = parsed?.category ?? "Uncategorised"
                editableFillPercent = parsed?.fillPercent
                editableRemainingVolume = parsed?.remainingVolume
                if let vol = parsed?.remainingVolume?.lowercased() {
                if vol.contains("ml") || vol.contains("மில") { editableUnit = "mL" }
                else if vol.contains("l") || vol.contains("லி") { editableUnit = "L" }
                }

                // Only attempt fuzzy match when a single product was returned
                if items.count == 1, let name = parsed?.name, let storage {
                    matchedExistingItem = storage.items.first {
                        $0.name.lowercased().contains(name.lowercased()) ||
                        name.lowercased().contains($0.name.lowercased())
                    }
                    if let existing = matchedExistingItem {
                        editableName     = existing.name
                        editableUnit     = existing.uom?.symbol ?? editableUnit
                        editableCategory = existing.category
                    }
                }

                step = .review
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                AnalyticsManager.shared.track(.smartCountFailed(mode: "photo", reason: error.localizedDescription))
                step = .capture
            }
        }
    }

    // MARK: - Logic: Save (single product)

    private func saveSingleItem() async {
        let name = editableName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let storage = selectedStorage
        guard let storage else {
            errorMessage = L("ai.selectStorage", "Please select a storage area.")
            return
        }

        let qty = Double(editableQty) ?? 0
        let matchedUOM = uoms.first { $0.symbol.lowercased() == editableUnit.lowercased() }

        if let existing = matchedExistingItem {
            let count = InventoryCount(previousQuantity: existing.currentQuantity, countedQuantity: qty, notes: "Photo inventory")
            existing.countHistory.append(count)
            existing.currentQuantity = qty
            if let parsed = parsedItem {
                existing.applyCapturedFields(from: parsed)
            }
            let event = ActivityEvent(
                eventType: "ItemCounted",
                itemName: existing.name,
                storageName: storage.name,
                quantityBefore: count.previousQuantity,
                quantityAfter: qty,
                notes: "Updated via photo inventory",
                performedBy: "You"
            )
            modelContext.insert(event)
        } else {
            guard !SubscriptionManager.shared.freeItemCapReached(storage: storage, context: modelContext) else {
                return
            }
            let item = InventoryItem(
                name: name,
                currentQuantity: qty,
                category: editableCategory,
                storage: storage,
                uom: matchedUOM
            )
            modelContext.insert(item)
            if let parsed = parsedItem {
                item.applyCapturedFields(from: parsed)
            }
            AnalyticsManager.shared.track(.itemAdded(
                category: item.category,
                hasBarcode: !item.barcode.isEmpty,
                hasPhoto: false,
                source: "ai",
                inputMethod: "photo"
            ))
            let event = ActivityEvent(
                eventType: "ItemAdded",
                itemName: name,
                storageName: storage.name,
                notes: "Added via photo inventory",
                performedBy: "You"
            )
            modelContext.insert(event)
        }

        modelContext.safeSave(context: "ImageInventorySingleSave")
        let extraFields = parsedItem.map { EditableItem(from: $0).capturedExtraFieldNames }
        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "photo",
            itemCount: 1,
            capturedExtraFields: extraFields?.isEmpty == false ? extraFields : nil
        ))
        onComplete?(1)
        dismiss()
    }

    // MARK: - Logic: Save (shelf scan — multiple products)

    private func saveAllItems() async {
        guard let storage = selectedStorage else { return }
        step = .saving

        let itemsToSave = parsedItems.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var runningCount = SubscriptionManager.shared.itemCount(in: storage, context: modelContext)
        var appliedCount = 0

        for editable in itemsToSave {
            let matchedUOM = uoms.first {
                $0.symbol.lowercased() == (editable.unitSymbol?.lowercased() ?? "")
            }

            switch editable.match {
            case .existing(let existing):
                let qty = editable.quantity ?? existing.currentQuantity
                let count = InventoryCount(
                    previousQuantity: existing.currentQuantity,
                    countedQuantity: qty,
                    notes: "Photo shelf scan"
                )
                existing.countHistory.append(count)
                existing.currentQuantity = qty
                existing.applyCapturedFields(from: editable)
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: storage.name,
                    quantityBefore: count.previousQuantity,
                    quantityAfter: qty,
                    notes: "Photo shelf scan",
                    performedBy: "You"
                )
                modelContext.insert(event)
                appliedCount += 1
            case .new:
                guard subscriptionManager.isPro || editable.isSelectedForAdd else { continue }
                guard SubscriptionManager.shared.canInsertNewItem(runningCount: &runningCount) else {
                    continue
                }
                let item = InventoryItem(
                    name: editable.name,
                    description: editable.aiNotes ?? "",
                    sku: editable.sku ?? "",
                    barcode: editable.barcode ?? "",
                    currentQuantity: editable.quantity ?? 0,
                    minQuantity: editable.minQuantity ?? 0,
                    unitCost: editable.unitCost ?? 0,
                    category: editable.category ?? "Uncategorised",
                    expiryDate: editable.expiryDate,
                    storage: storage,
                    uom: matchedUOM
                )
                if let sellingPrice = editable.sellingPrice {
                    item.sellingPrice = sellingPrice
                }
                modelContext.insert(item)
                AnalyticsManager.shared.track(.itemAdded(
                    category: item.category,
                    hasBarcode: !(editable.barcode?.isEmpty ?? true),
                    hasPhoto: false,
                    source: "ai",
                    inputMethod: "photo"
                ))
                let event = ActivityEvent(
                    eventType: "ItemAdded",
                    itemName: item.name,
                    storageName: storage.name,
                    notes: "Added via photo shelf scan",
                    performedBy: "You"
                )
                modelContext.insert(event)
                appliedCount += 1
            }
        }

        modelContext.safeSave(context: "ImageInventoryShelfSave")

        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "photo",
            itemCount: appliedCount,
            capturedExtraFields: {
                let fields = Array(Set(itemsToSave.flatMap(\.capturedExtraFieldNames)))
                return fields.isEmpty ? nil : fields
            }()
        ))

        Task {
            for item in storage.items {
                FirestoreManager.shared.syncItem(item)
            }
        }

        onComplete?(appliedCount)
        dismiss()
    }
}

// MARK: - CameraPickerView

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
