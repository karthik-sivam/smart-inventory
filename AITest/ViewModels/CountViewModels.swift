import Foundation
import SwiftUI
import SwiftData

@MainActor
final class CountViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedStorage: Storage?
    @Published private(set) var filteredItems: [InventoryItem] = []

    private var items: [InventoryItem] = []

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

    private func applyFilters() {
        var result = items
        if let storage = selectedStorage {
            result = result.filter { $0.storage?.id == storage.id }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.sku.localizedCaseInsensitiveContains(searchText) }
        }
        filteredItems = result
    }
}


