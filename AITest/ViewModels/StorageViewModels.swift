import Foundation
import SwiftUI
import SwiftData

// MARK: - StorageListViewModel

@MainActor
final class StorageListViewModel: ObservableObject {
    static let freeStorageCap = SubscriptionManager.freeStorageLimit

    @Published var searchText: String = ""
    @Published private(set) var filteredStorages: [Storage] = []

    private var storages: [Storage] = []

    var isAtFreeStorageCap: Bool {
        !SubscriptionManager.shared.isPro && storages.count >= Self.freeStorageCap
    }

    var freeStorageUsageText: String? {
        guard !SubscriptionManager.shared.isPro else { return nil }
        return "\(storages.count) of \(Self.freeStorageCap) storages used"
    }
    private var modelContext: ModelContext?

    func bind(modelContext: ModelContext?, storages: [Storage]) {
        self.modelContext = modelContext
        self.storages = storages
        applyFilters()
    }

    func updateStorages(_ storages: [Storage]) {
        self.storages = storages
        applyFilters()
    }

    func setSearchText(_ text: String) {
        searchText = text
        applyFilters()
    }

    func deleteStorage(_ storage: Storage) {
        guard let modelContext else { return }

        // Soft-delete in Firestore BEFORE removing locally
        // (items are cascade-deleted with the storage, so we delete them
        //  in Firestore first while their storageID is still accessible)
        for item in storage.items {
            FirestoreManager.shared.deleteItem(item)
        }
        FirestoreManager.shared.deleteStorage(storage)

        // Remove locally (cascade deletes items via SwiftData relationship)
        AnalyticsManager.shared.track(.storageDeleted)
        modelContext.delete(storage)
        modelContext.safeSave(context: "storageViewModel save")
        AdManager.shared.recordCompletion(event: .storageUpdated)
    }

    private func applyFilters() {
        if searchText.isEmpty {
            filteredStorages = storages
        } else {
            filteredStorages = storages.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - StorageDetailViewModel

@MainActor
final class StorageDetailViewModel: ObservableObject {
    func lowStockCount(for storage: Storage) -> Int {
        storage.items.filter { $0.isLowStock }.count
    }
}
