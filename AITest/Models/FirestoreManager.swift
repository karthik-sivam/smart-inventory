import Foundation
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

// MARK: - FirestoreManager
//
// Architecture: SwiftData-first, Firestore as cloud sync layer.
//
// SwiftData remains the single source of truth for the UI (@Query works as-is).
// Every write to SwiftData is mirrored to Firestore.
// On first login or app install, cloud data is pulled into SwiftData.
//
// Firestore data model:
//   users/{uid}/
//     profile:        { displayName, email, currency, createdAt, lastSyncAt }
//     storages/{id}:  { name, location, storageDescription, color, createdAt, updatedAt, isDeleted }
//       items/{id}:   { name, sku, barcode, description, currentQty, minQty, maxQty,
//                       unitCost, isOutOfStock, uomName, uomSymbol, uomCategory,
//                       createdAt, updatedAt, isDeleted }
//         counts/{id}: { previousQty, countedQty, reason, notes, countedBy, countDate }
//
// Sync strategy:
//   - Writes: fire-and-forget async (never block the UI)
//   - Reads: pull on login / pull-to-refresh (no real-time listeners in v1 — keeps costs low)
//   - Conflict resolution: last-write-wins on updatedAt timestamp
//   - Soft deletes: isDeleted flag so we can tombstone across devices

@MainActor
class FirestoreManager: ObservableObject {

    @Published var syncState: SyncState = .idle
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    static let shared = FirestoreManager()

    private let db = Firestore.firestore()
    private var currentUID: String? { Auth.auth().currentUser?.uid }

    enum SyncState: Equatable {
        case idle
        case syncing
        case success
        case failed(String)

        var description: String {
            switch self {
            case .idle:           return "Not synced"
            case .syncing:        return "Syncing…"
            case .success:        return "Synced"
            case .failed(let msg): return "Sync failed: \(msg)"
            }
        }

        var icon: String {
            switch self {
            case .idle:    return "icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .success: return "checkmark.icloud"
            case .failed:  return "xmark.icloud"
            }
        }

        var color: Color {
            switch self {
            case .idle:    return .secondary
            case .syncing: return .blue
            case .success: return .green
            case .failed:  return .red
            }
        }
    }

    private init() {}

    // MARK: - Root Reference

    private func userRef() throws -> DocumentReference {
        guard let uid = currentUID else {
            throw FirestoreError.notAuthenticated
        }
        return db.collection("users").document(uid)
    }

    // MARK: - Errors

    enum FirestoreError: LocalizedError {
        case notAuthenticated
        case encodingFailed(String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:      return "User not logged in. Cannot sync data."
            case .encodingFailed(let m): return "Failed to encode data: \(m)"
            case .decodingFailed(let m): return "Failed to decode data: \(m)"
            }
        }
    }

    // MARK: - Profile Sync

    func saveUserProfile(currency: String) {
        Task {
            guard let ref = try? userRef() else { return }
            let data: [String: Any] = [
                "currency": currency,
                "lastSyncAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try? await ref.setData(data, merge: true)
        }
    }

    // MARK: - Storage CRUD

    /// Push a storage area to Firestore. Call after every SwiftData write.
    func syncStorage(_ storage: Storage) {
        Task {
            await pushStorage(storage)
        }
    }

    /// Soft-delete a storage (and its items) in Firestore.
    func deleteStorage(_ storage: Storage) {
        Task {
            guard let ref = try? userRef() else { return }
            let storageRef = ref.collection("storages").document(storage.id.uuidString)
            try? await storageRef.updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }
    }

    private func pushStorage(_ storage: Storage) async {
        guard let ref = try? userRef() else { return }
        let data: [String: Any] = [
            "id": storage.id.uuidString,
            "name": storage.name,
            "location": storage.location,
            "storageDescription": storage.storageDescription,
            "color": storage.color,
            "createdAt": Timestamp(date: storage.createdAt),
            "updatedAt": Timestamp(date: storage.updatedAt),
            "isDeleted": false
        ]
        let docRef = ref.collection("storages").document(storage.id.uuidString)
        do {
            try await docRef.setData(data, merge: true)
        } catch {
            print("Firestore: Failed to sync storage '\(storage.name)' — \(error.localizedDescription)")
        }
    }

    // MARK: - Item CRUD

    /// Push an inventory item to Firestore. Call after every SwiftData write.
    func syncItem(_ item: InventoryItem) {
        Task {
            await pushItem(item)
        }
    }

    /// Soft-delete an item in Firestore.
    func deleteItem(_ item: InventoryItem) {
        Task {
            guard let ref = try? userRef() else { return }
            guard let storageID = item.storage?.id.uuidString else { return }
            let itemRef = ref
                .collection("storages").document(storageID)
                .collection("items").document(item.id.uuidString)
            try? await itemRef.updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }
    }

    private func pushItem(_ item: InventoryItem) async {
        guard let ref = try? userRef() else { return }
        guard let storageID = item.storage?.id.uuidString else {
            print("Firestore: Item '\(item.name)' has no storage — skipping sync.")
            return
        }
        let data: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "itemDescription": item.itemDescription,
            "sku": item.sku,
            "barcode": item.barcode,
            "currentQuantity": item.currentQuantity,
            "minQuantity": item.minQuantity,
            "maxQuantity": item.maxQuantity,
            "unitCost": item.unitCost,
            "isOutOfStock": item.isOutOfStock,
            "uomName": item.uom?.name ?? "",
            "uomSymbol": item.uom?.symbol ?? "",
            "uomCategory": item.uom?.category ?? "",
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": Timestamp(date: item.updatedAt),
            "isDeleted": false
        ]
        let docRef = ref
            .collection("storages").document(storageID)
            .collection("items").document(item.id.uuidString)
        do {
            try await docRef.setData(data, merge: true)
        } catch {
            print("Firestore: Failed to sync item '\(item.name)' — \(error.localizedDescription)")
        }
    }

    // MARK: - Inventory Count Sync

    func syncCount(_ count: InventoryCount, for item: InventoryItem) {
        Task {
            guard let userDocument = try? userRef() else { return }
            guard let storageID = item.storage?.id.uuidString else { return }
            let data: [String: Any] = [
                "id": count.id.uuidString,
                "previousQuantity": count.previousQuantity,
                "countedQuantity": count.countedQuantity,
                "adjustmentReason": count.adjustmentReason,
                "notes": count.notes,
                "countedBy": count.countedBy,
                "countDate": Timestamp(date: count.countDate)
            ]
            let countRef = userDocument
                .collection("storages").document(storageID)
                .collection("items").document(item.id.uuidString)
                .collection("counts").document(count.id.uuidString)
            try? await countRef.setData(data, merge: true)
        }
    }

    // MARK: - Full Sync (Pull from Cloud → Local SwiftData)

    /// Pull all cloud data and merge into local SwiftData.
    /// Returns the number of storages found in Firestore (0 = cloud is empty for this user).
    /// Call on login, on app foreground, or on user-initiated refresh.
    @discardableResult
    func pullFromCloud(modelContext: ModelContext) async -> Int {
        guard let ref = try? userRef() else {
            syncState = .failed("Not logged in")
            return 0
        }

        syncState = .syncing
        errorMessage = nil

        do {
            let storageSnapshot = try await ref.collection("storages")
                .whereField("isDeleted", isEqualTo: false)
                .getDocuments()

            let cloudStorageCount = storageSnapshot.documents.count

            for storageDoc in storageSnapshot.documents {
                let d = storageDoc.data()
                guard let idString = d["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let name = d["name"] as? String else { continue }

                let descriptor = FetchDescriptor<Storage>(
                    predicate: #Predicate { $0.id == id }
                )
                let existing = try? modelContext.fetch(descriptor)
                let storage: Storage

                if let found = existing?.first {
                    // Update if cloud is newer
                    let cloudUpdated = (d["updatedAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                    if cloudUpdated > found.updatedAt {
                        found.name = name
                        found.location = d["location"] as? String ?? ""
                        found.storageDescription = d["storageDescription"] as? String ?? ""
                        found.color = d["color"] as? String ?? "#007AFF"
                        found.updatedAt = cloudUpdated
                    }
                    storage = found
                } else {
                    // Insert new storage from cloud
                    let newStorage = Storage(
                        name: name,
                        location: d["location"] as? String ?? "",
                        description: d["storageDescription"] as? String ?? "",
                        color: d["color"] as? String ?? "#007AFF"
                    )
                    newStorage.id = id
                    if let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() {
                        newStorage.createdAt = createdAt
                    }
                    modelContext.insert(newStorage)
                    storage = newStorage
                }

                // Pull items for this storage
                let itemSnapshot = try await storageDoc.reference.collection("items")
                    .whereField("isDeleted", isEqualTo: false)
                    .getDocuments()

                for itemDoc in itemSnapshot.documents {
                    try await mergeItem(from: itemDoc.data(), into: storage, modelContext: modelContext)
                }
            }

            try modelContext.save()
            syncState = .success
            lastSyncDate = Date()
            print("Firestore ✅ Pull complete — \(cloudStorageCount) storages synced.")
            return cloudStorageCount

        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            print("Firestore ❌ Pull failed — \(error.localizedDescription)")
            return 0
        }
    }

    /// Push ALL local SwiftData to Firestore.
    /// Call on first login to migrate existing local data to the cloud.
    func pushAllToCloud(storages: [Storage], items: [InventoryItem]) async {
        guard currentUID != nil else { return }

        syncState = .syncing
        errorMessage = nil

        for storage in storages {
            await pushStorage(storage)
        }
        for item in items {
            await pushItem(item)
        }

        syncState = .success
        lastSyncDate = Date()
        print("Firestore ✅ Full push complete — \(storages.count) storages, \(items.count) items.")
    }

    // MARK: - Private Helpers

    private func mergeItem(
        from data: [String: Any],
        into storage: Storage,
        modelContext: ModelContext
    ) async throws {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String else { return }

        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate { $0.id == id }
        )
        let existing = try? modelContext.fetch(descriptor)

        if let found = existing?.first {
            let cloudUpdated = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            if cloudUpdated > found.updatedAt {
                found.name = name
                found.itemDescription = data["itemDescription"] as? String ?? ""
                found.sku = data["sku"] as? String ?? ""
                found.barcode = data["barcode"] as? String ?? ""
                found.currentQuantity = data["currentQuantity"] as? Double ?? 0
                found.minQuantity = data["minQuantity"] as? Double ?? 0
                found.maxQuantity = data["maxQuantity"] as? Double ?? 0
                found.unitCost = data["unitCost"] as? Double ?? 0
                found.isOutOfStock = data["isOutOfStock"] as? Bool ?? false
                found.updatedAt = cloudUpdated
            }
        } else {
            let newItem = InventoryItem(
                name: name,
                description: data["itemDescription"] as? String ?? "",
                sku: data["sku"] as? String ?? "",
                barcode: data["barcode"] as? String ?? "",
                currentQuantity: data["currentQuantity"] as? Double ?? 0,
                minQuantity: data["minQuantity"] as? Double ?? 0,
                maxQuantity: data["maxQuantity"] as? Double ?? 0,
                unitCost: data["unitCost"] as? Double ?? 0,
                isOutOfStock: data["isOutOfStock"] as? Bool ?? false,
                storage: storage
            )
            newItem.id = id
            if let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() {
                newItem.createdAt = createdAt
            }
            modelContext.insert(newItem)
        }
    }
}

// MARK: - Sync Status View

/// Small cloud badge to show in navigation bars.
struct SyncStatusBadge: View {
    @ObservedObject var firestoreManager = FirestoreManager.shared

    var body: some View {
        HStack(spacing: 4) {
            if case .syncing = firestoreManager.syncState {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            } else {
                Image(systemName: firestoreManager.syncState.icon)
                    .font(.caption)
                    .foregroundColor(firestoreManager.syncState.color)
            }

            if let lastSync = firestoreManager.lastSyncDate {
                Text(lastSync, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
