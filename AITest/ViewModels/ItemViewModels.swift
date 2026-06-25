import Foundation
import SwiftUI
import SwiftData

// MARK: - ItemListViewModel

@MainActor
final class ItemListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedStorage: Storage?
    /// `nil` means "All" categories.
    @Published var selectedCategory: String?
    @Published private(set) var filteredItems: [InventoryItem] = []

    private var items: [InventoryItem] = []
    private var storages: [Storage] = []
    private var modelContext: ModelContext?
    private var searchDebounceTask: Task<Void, Never>?

    func bind(modelContext: ModelContext?, items: [InventoryItem], storages: [Storage]) {
        self.modelContext = modelContext
        self.items = items
        self.storages = storages
        applyFilters()
    }

    func updateItems(_ items: [InventoryItem]) {
        self.items = items
        applyFilters()
    }

    func updateStorages(_ storages: [Storage]) {
        self.storages = storages
        if let sel = selectedStorage, !storages.contains(where: { $0.id == sel.id }) {
            selectedStorage = nil
        }
        applyFilters()
    }

    func setSelectedStorage(_ storage: Storage?) {
        selectedStorage = storage
        applyFilters()
    }

    func setSearchText(_ text: String) {
        searchText = text
        searchDebounceTask?.cancel()
        if text.isEmpty {
            applyFilters()
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
            guard !Task.isCancelled else { return }
            applyFilters()
        }
    }

    func setSelectedCategory(_ category: String?) {
        selectedCategory = category
        applyFilters()
    }

    func deleteItem(_ item: InventoryItem) {
        guard let modelContext else { return }
        // Record the event BEFORE deletion so item.storage is still accessible.
        let event = ActivityEvent(
            eventType: "ItemDeleted",
            itemName: item.name,
            storageName: item.storage?.name ?? "Unknown",
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "deleteItem activity event")
        FirestoreManager.shared.syncActivity(event)
        // Soft-delete in Firestore (still needs item.storage?.id).
        FirestoreManager.shared.deleteItem(item)
        SpotlightManager.shared.deindex(item)
        modelContext.delete(item)
        modelContext.safeSave(context: "deleteItem")
        AdManager.shared.recordCompletion(event: .itemUpdated)
    }

    private func applyFilters() {
        var result = items
        if let storage = selectedStorage {
            result = result.filter { $0.storage?.id == storage.id }
        }
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.sku.lowercased().contains(q) ||
                $0.barcode.lowercased().contains(q) ||
                $0.itemDescription.lowercased().contains(q) ||
                $0.category.lowercased().contains(q) ||
                ($0.storage?.name.lowercased().contains(q) ?? false) ||
                ($0.storage?.location.lowercased().contains(q) ?? false)
            }
        }
        filteredItems = result
    }
}

// MARK: - ItemFormViewModel

@MainActor
final class ItemFormViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var sku: String = ""
    @Published var barcode: String = ""
    @Published var currentQuantity: String = ""
    @Published var minQuantity: String = ""
    @Published var maxQuantity: String = ""
    @Published var unitCost: String = ""
    @Published var reorderPercentage: Double = 0
    @Published var lastPurchasePrice: String = ""
    @Published var selectedStorage: Storage?
    @Published var selectedUOM: UOM?
    @Published var category: String = "Uncategorised"
    @Published var hasExpiryDate: Bool = false
    @Published var expiryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @Published var existingPhotoURL: String? = nil
    /// Drives the "Looking up product..." banner in Add/Edit Item forms while
    /// a barcode enrichment lookup is in flight. Phase 3 — Pro only.
    @Published var isEnriching: Bool = false
    /// Tracks which template was used to pre-fill this add-item form (if any).
    var sourceTemplateId: UUID? = nil

    private var modelContext: ModelContext?

    func bind(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    /// Phase 3 — Pro-only smart barcode enrichment. Looks the scanned code up
    /// in external product databases (Open Food Facts → UPCItemDB) and
    /// pre-fills the form fields that are still empty. Free users get no
    /// network call; the barcode field is still populated by the caller.
    ///
    /// Field-fill semantics:
    ///   - `name`         — filled only if empty
    ///   - `description`  — filled only if empty
    ///   - `category`     — filled only if still `"Uncategorised"`
    ///   - `selectedUOM`  — filled only if nil OR the current selection is
    ///                      the default UOM (i.e. the user hasn't deliberately
    ///                      picked one yet)
    /// Never overwrites user-entered values.
    @MainActor
    func enrichFromBarcode(_ barcode: String, uoms: [UOM]) async {
        guard SubscriptionManager.shared.isPro else {
            AnalyticsManager.shared.track(.barcodeScanResult(found: false, enriched: false))
            return
        }
        guard !barcode.isEmpty else { return }
        isEnriching = true
        defer { isEnriching = false }
        guard let product = await BarcodeEnrichmentService.shared.enrich(barcode: barcode) else {
            AnalyticsManager.shared.track(.barcodeScanResult(found: false, enriched: false))
            return
        }
        AnalyticsManager.shared.track(.barcodeScanResult(found: true, enriched: true))
        if name.isEmpty                { name = product.name }
        if description.isEmpty         { description = product.description }
        if category == "Uncategorised" { category = product.category }
        if selectedUOM == nil || selectedUOM?.isDefault == true {
            if let matched = uoms.first(where: { $0.symbol == product.uomSymbol }) {
                selectedUOM = matched
            }
        }
    }

    func load(from item: InventoryItem) {
        name            = item.name
        description     = item.itemDescription
        sku             = item.sku
        barcode         = item.barcode
        // Quantities use smartFormatted so whole numbers show as "5" not "5.00".
        currentQuantity = item.currentQuantity.smartFormatted
        minQuantity     = item.minQuantity.smartFormatted
        maxQuantity     = item.maxQuantity.smartFormatted
        // Unit cost keeps %.2f — currency should always show two decimals.
        unitCost        = String(format: "%.2f", item.unitCost)
        reorderPercentage = item.reorderPercentage
        lastPurchasePrice = item.lastPurchasePrice > 0
            ? String(format: "%.2f", item.lastPurchasePrice)
            : ""
        selectedStorage = item.storage
        selectedUOM     = item.uom
        category        = item.category
        hasExpiryDate   = item.expiryDate != nil
        if let d = item.expiryDate { expiryDate = d }
        existingPhotoURL = item.photoURL
    }

    var canSaveNew: Bool {
        !name.isEmpty && selectedStorage != nil && selectedUOM != nil
    }

    var canSaveEdit: Bool {
        !name.isEmpty && !currentQuantity.isEmpty
    }

    func saveNew() {
        guard let modelContext else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if selectedUOM == nil {
            let uoms = (try? modelContext.fetch(FetchDescriptor<UOM>())) ?? []
            selectedUOM = uoms.first(where: { $0.isDefault }) ?? uoms.first
        }
        if selectedStorage == nil {
            let storages = (try? modelContext.fetch(FetchDescriptor<Storage>())) ?? []
            selectedStorage = storages.first(where: { $0.name == "Test Warehouse" }) ?? storages.first
        }
        guard let uom = selectedUOM, let storage = selectedStorage else { return }

        let qty = Double(currentQuantity) ?? 0
        let item = InventoryItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            sku: sku,
            barcode: barcode,
            currentQuantity: qty,
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
        if hasExpiryDate, let expiry = item.expiryDate, qty > 0 {
            let initialBatch = InventoryBatch(
                quantity: qty,
                expiryDate: expiry,
                notes: "Initial stock",
                item: item
            )
            modelContext.insert(initialBatch)
        }

        modelContext.safeSave(context: "saveNew item")

        AnalyticsManager.shared.track(.itemAdded(
            category: item.category,
            hasBarcode: !item.barcode.isEmpty,
            hasPhoto: item.photoURL != nil
        ))

        let event = ActivityEvent(
            eventType: "ItemAdded",
            itemName: name,
            storageName: selectedStorage?.name ?? "Unknown",
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "saveNew activity event")
        FirestoreManager.shared.syncActivity(event)

        // Sync to Firestore (fire-and-forget — never blocks the UI)
        FirestoreManager.shared.syncItem(item)
        SpotlightManager.shared.index(item)

        AdManager.shared.recordCompletion(event: .itemAdded)
    }

    func saveEdits(to item: InventoryItem) {
        let previousQty = item.currentQuantity
        item.name            = name
        item.itemDescription = description
        item.sku             = sku.isEmpty ? "SKU-\(UUID().uuidString.prefix(6))" : sku
        item.barcode         = barcode
        let newQty           = Double(currentQuantity) ?? 0
        item.currentQuantity = newQty
        item.minQuantity     = Double(minQuantity) ?? 0
        item.maxQuantity     = Double(maxQuantity) ?? 0
        item.unitCost        = Double(unitCost) ?? 0
        item.reorderPercentage = reorderPercentage
        let newLastPrice = Double(lastPurchasePrice) ?? 0
        if newLastPrice > 0 {
            if newLastPrice != item.lastPurchasePrice {
                item.lastPurchasedAt = Date()
            }
            item.lastPurchasePrice = newLastPrice
        } else {
            item.lastPurchasePrice = 0
            item.lastPurchasedAt = nil
        }
        item.storage         = selectedStorage
        item.uom             = selectedUOM
        item.category        = category
        item.expiryDate      = hasExpiryDate ? expiryDate : nil
        item.updatedAt       = Date()
        modelContext?.safeSave(context: "saveEdits item")

        if let ctx = modelContext {
            let editEvent = ActivityEvent(
                eventType: "ItemUpdated",
                itemName: name,
                storageName: selectedStorage?.name ?? "Unknown",
                quantityBefore: previousQty,
                quantityAfter: Double(currentQuantity) ?? previousQty,
                performedBy: AuthManager.shared.actorName
            )
            ctx.insert(editEvent)
            ctx.safeSave(context: "saveEdits activity event")
            FirestoreManager.shared.syncActivity(editEvent)
        }

        // Sync to Firestore
        FirestoreManager.shared.syncItem(item)
        SpotlightManager.shared.index(item)

        AdManager.shared.recordCompletion(event: .itemUpdated)
    }
}

// MARK: - ItemDetailViewModel

@MainActor
final class ItemDetailViewModel: ObservableObject {
    private var modelContext: ModelContext?

    func bind(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    /// `isOutOfStock` is derived from `currentQuantity` and cannot be toggled independently.
    /// Use `markOutOfStock` to set quantity to zero when the user confirms.
    func markOutOfStock(for item: InventoryItem) {
        let previousQty = item.currentQuantity
        item.currentQuantity = 0
        item.updatedAt = Date()
        modelContext?.safeSave(context: "markOutOfStock")

        FirestoreManager.shared.syncItem(item)

        let zeroEvent = ActivityEvent(
            eventType: "ItemCounted",
            itemName: item.name,
            storageName: item.storage?.name ?? "Unknown",
            quantityBefore: previousQty,
            quantityAfter: 0,
            notes: "Set to zero",
            performedBy: AuthManager.shared.actorName
        )
        modelContext?.insert(zeroEvent)
        modelContext?.safeSave(context: "markOutOfStock activity event")
        FirestoreManager.shared.syncActivity(zeroEvent)

        AdManager.shared.recordCompletion(event: .itemUpdated)
    }

    func delete(_ item: InventoryItem) {
        guard let modelContext else { return }
        let event = ActivityEvent(
            eventType: "ItemDeleted",
            itemName: item.name,
            storageName: item.storage?.name ?? "Unknown",
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "delete activity event")
        FirestoreManager.shared.syncActivity(event)
        // Soft-delete in Firestore first (needs storage ID before local removal)
        FirestoreManager.shared.deleteItem(item)
        SpotlightManager.shared.deindex(item)
        AnalyticsManager.shared.track(.itemDeleted(category: item.category))
        modelContext.delete(item)
        modelContext.safeSave(context: "delete item")
        AdManager.shared.recordCompletion(event: .itemUpdated)
    }
}

// MARK: - CountItemViewModel

@MainActor
final class CountItemViewModel: ObservableObject {
    @Published var countedQuantity: String = ""
    @Published var adjustmentReason: String = ""
    @Published var notes: String = ""

    private var modelContext: ModelContext?

    func bind(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    func saveCount(for item: InventoryItem) {
        guard let modelContext, let newQuantity = Double(countedQuantity) else { return }

        let previousQty = item.currentQuantity

        let count = InventoryCount(
            previousQuantity: previousQty,
            countedQuantity: newQuantity,
            adjustmentReason: adjustmentReason,
            notes: notes,
            item: item
        )
        // Explicitly append to countHistory so the inverse relationship is
        // always populated regardless of SwiftData's auto-linking behavior.
        item.countHistory.append(count)
        item.currentQuantity = newQuantity
        item.updatedAt       = Date()
        modelContext.insert(count)
        modelContext.safeSave(context: "saveCount")

        AnalyticsManager.shared.track(.itemCounted(storageName: item.storage?.name ?? "Unknown"))

        let event = ActivityEvent(
            eventType: "ItemCounted",
            itemName: item.name,
            storageName: item.storage?.name ?? "Unknown",
            quantityBefore: previousQty,
            quantityAfter: newQuantity,
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "count activity event")
        FirestoreManager.shared.syncActivity(event)

        // Sync both the updated item quantity and the new count record to Firestore
        FirestoreManager.shared.syncItem(item)
        FirestoreManager.shared.syncCount(count, for: item)

        AdManager.shared.recordCompletion(event: .inventoryCountCompleted)
    }
}
