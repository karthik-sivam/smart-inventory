import Foundation
import SwiftUI
import SwiftData

@MainActor
final class CountViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedStorage: Storage?
    @Published private(set) var filteredItems: [InventoryItem] = []

    // Session tracking — in-memory only, resets when tab is revisited
    var countedThisSession: Set<UUID> = []

    // Status filter — `.due` is the default priority queue (never counted, or
    // last count older than 7 days).
    enum StatusFilter: Equatable {
        case due        // default — never counted OR last count > 7 days ago
        case uncounted  // never counted only
        case lowStock   // low stock or out of stock
        case all        // every item regardless of count recency
    }

    @Published var statusFilter: StatusFilter = .due

    private let auditDueInterval: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    private var items: [InventoryItem] = []

    private func isDueForAudit(_ item: InventoryItem) -> Bool {
        guard let lastCount = item.countHistory.map(\.countDate).max() else {
            return true  // never counted → always due
        }
        return Date().timeIntervalSince(lastCount) > auditDueInterval
    }

    func bind(items: [InventoryItem]) {
        self.items = items
        applyFilters()
    }

    func updateItems(_ items: [InventoryItem]) {
        self.items = items
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

    func setStatusFilter(_ f: StatusFilter) {
        statusFilter = f
        applyFilters()
    }

    func markCounted(_ itemID: UUID) {
        countedThisSession.insert(itemID)
        objectWillChange.send()
    }

    private func applyFilters() {
        var result = items

        // Storage filter
        if let storage = selectedStorage {
            result = result.filter { $0.storage?.id == storage.id }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.sku.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Status filter
        switch statusFilter {
        case .due:
            result = result.filter { isDueForAudit($0) }
        case .uncounted:
            result = result.filter { $0.countHistory.isEmpty }
        case .lowStock:
            result = result.filter { $0.isLowStock || $0.isOutOfStock }
        case .all:
            break
        }

        // Smart sort:
        // 1. Never counted (no countHistory) — first
        // 2. Counted longest ago — second
        // 3. Recently counted — last
        // 4. Within each group, alphabetically by name
        result.sort { a, b in
            let aDate = a.countHistory.map(\.countDate).max()
            let bDate = b.countHistory.map(\.countDate).max()

            switch (aDate, bDate) {
            case (nil, nil):
                return a.name < b.name
            case (nil, _):
                return true  // a never counted → goes first
            case (_, nil):
                return false // b never counted → b goes first
            case let (aD?, bD?):
                if aD == bD { return a.name < b.name }
                return aD < bD  // older count date → earlier in list
            }
        }

        filteredItems = result
    }
}
