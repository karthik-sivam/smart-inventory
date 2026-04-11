import Foundation
import SwiftUI
import SwiftData

// MARK: - ItemListViewModel

@MainActor
final class ItemListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedStorage: Storage?
    @Published private(set) var filteredItems: [InventoryItem] = []

    private var items: [InventoryItem] = []
    private var storages: [Storage] = []
    private var modelContext: ModelContext?

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
        applyFilters()
    }

    func deleteItem(_ item: InventoryItem) {
        guard let modelContext else { return }
        // 1. Soft-delete in Firestore BEFORE removing from SwiftData
        //    (we still need item.storage?.id at this point)
        FirestoreManager.shared.deleteItem(item)
        // 2. Remove locally
        modelContext.delete(item)
        try? modelContext.save()
        AdManager.shared.recordCompletion(event: .itemUpdated)
    }

    private func applyFilters() {
        var result = items
        if let storage = selectedStorage {
            result = result.filter { $0.storage?.id == storage.id }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.sku.localizedCaseInsensitiveContains(searchText)
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
    @Published var selectedStorage: Storage?
    @Published var selectedUOM: UOM?
    @Published var isOutOfStock: Bool = false

    private var modelContext: ModelContext?

    func bind(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    func load(from item: InventoryItem) {
        name            = item.name
        description     = item.itemDescription
        sku             = item.sku
        barcode         = item.barcode
        currentQuantity = String(format: "%.2f", item.currentQuantity)
        minQuantity     = String(format: "%.2f", item.minQuantity)
        maxQuantity     = String(format: "%.2f", item.maxQuantity)
        unitCost        = String(format: "%.2f", item.unitCost)
        selectedStorage = item.storage
        selectedUOM     = item.uom
        isOutOfStock    = item.isOutOfStock
    }

    var canSaveNew: Bool {
        !name.isEmpty && selectedStorage != nil && selectedUOM != nil
    }

    var canSaveEdit: Bool {
        !name.isEmpty && !currentQuantity.isEmpty
    }

    func saveNew() {
        guard let modelContext else { return }
        let qty = Double(currentQuantity) ?? 0
        let item = InventoryItem(
            name: name,
            description: description,
            sku: sku,
            barcode: barcode,
            currentQuantity: qty,
            minQuantity: Double(minQuantity) ?? 0,
            maxQuantity: Double(maxQuantity) ?? 0,
            unitCost: Double(unitCost) ?? 0,
            isOutOfStock: qty <= 0,
            storage: selectedStorage,
            uom: selectedUOM
        )
        modelContext.insert(item)
        try? modelContext.save()

        // Sync to Firestore (fire-and-forget — never blocks the UI)
        FirestoreManager.shared.syncItem(item)

        AdManager.shared.recordCompletion(event: .itemAdded)
    }

    func saveEdits(to item: InventoryItem) {
        item.name            = name
        item.itemDescription = description
        item.sku             = sku.isEmpty ? "SKU-\(UUID().uuidString.prefix(6))" : sku
        item.barcode         = barcode
        let newQty           = Double(currentQuantity) ?? 0
        item.currentQuantity = newQty
        item.minQuantity     = Double(minQuantity) ?? 0
        item.maxQuantity     = Double(maxQuantity) ?? 0
        item.unitCost        = Double(unitCost) ?? 0
        item.storage         = selectedStorage
        item.uom             = selectedUOM
        item.isOutOfStock    = newQty <= 0 ? true : isOutOfStock
        item.updatedAt       = Date()
        try? modelContext?.save()

        // Sync to Firestore
        FirestoreManager.shared.syncItem(item)

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

    func toggleOutOfStock(for item: InventoryItem, to newValue: Bool) {
        item.isOutOfStock = newValue
        item.updatedAt    = Date()
        try? modelContext?.save()

        // Sync to Firestore
        FirestoreManager.shared.syncItem(item)

        AdManager.shared.recordCompletion(event: .itemUpdated)
    }

    func delete(_ item: InventoryItem) {
        guard let modelContext else { return }
        // Soft-delete in Firestore first (needs storage ID before local removal)
        FirestoreManager.shared.deleteItem(item)
        modelContext.delete(item)
        try? modelContext.save()
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

        let count = InventoryCount(
            previousQuantity: item.currentQuantity,
            countedQuantity: newQuantity,
            adjustmentReason: adjustmentReason,
            notes: notes,
            item: item
        )
        item.currentQuantity = newQuantity
        item.isOutOfStock    = newQuantity <= 0
        item.updatedAt       = Date()
        modelContext.insert(count)
        try? modelContext.save()

        // Sync both the updated item quantity and the new count record to Firestore
        FirestoreManager.shared.syncItem(item)
        FirestoreManager.shared.syncCount(count, for: item)

        AdManager.shared.recordCompletion(event: .inventoryCountCompleted)
    }
}
