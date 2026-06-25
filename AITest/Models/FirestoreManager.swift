import Foundation
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - PendingWrite

/// Persisted queue of Firestore writes that failed (typically offline).
struct PendingWrite: Codable {
    enum Kind: String, Codable { case item, storage }
    let id: UUID
    let kind: Kind
    let entityId: String
    let queuedAt: Date
}

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
//     storages/{id}:  { name, location, storageDescription, color, supplierEmail, createdAt, updatedAt, isDeleted }
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

    // Keyed by entity UUID. Each value is a pending Task that fires the actual
    // Firestore write after a short delay (cancel-and-replace on rapid calls).
    private var pendingItemTasks: [String: Task<Void, Never>] = [:]
    private var pendingStorageTasks: [String: Task<Void, Never>] = [:]
    private let debounceDuration: UInt64 = 1_500_000_000  // 1.5 seconds
    private let pendingWritesKey = "stoqly_pendingWrites"

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

    /// Uploads JPEG photo data to Firebase Storage and returns the download URL string.
    /// Path: items/{uid}/{itemId}.jpg
    func uploadItemPhoto(_ imageData: Data, itemId: UUID) async throws -> String {
        guard let uid = TeamManager.shared.effectiveUID else {
            throw URLError(.userAuthenticationRequired)
        }
        let ref = FirebaseStorage.Storage.storage().reference()
            .child("items/\(uid)/\(itemId.uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    /// Deletes the photo for an item from Firebase Storage.
    func deleteItemPhoto(itemId: UUID) {
        guard let uid = TeamManager.shared.effectiveUID else { return }
        let ref = FirebaseStorage.Storage.storage().reference()
            .child("items/\(uid)/\(itemId.uuidString).jpg")
        Task { try? await ref.delete() }
    }

    // MARK: - Root Reference

    private func userRef() throws -> DocumentReference {
        guard let uid = TeamManager.shared.effectiveUID else {
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

    /// Push a storage area to Firestore. Debounced — rapid updates collapse to one write.
    func syncStorage(_ storage: Storage) {
        let key = storage.id.uuidString
        pendingStorageTasks[key]?.cancel()
        pendingStorageTasks[key] = Task {
            try? await Task.sleep(nanoseconds: debounceDuration)
            guard !Task.isCancelled else { return }
            await pushStorage(storage)
            pendingStorageTasks.removeValue(forKey: key)
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
            "supplierEmail": storage.supplierEmail,
            "createdAt": Timestamp(date: storage.createdAt),
            "updatedAt": Timestamp(date: storage.updatedAt),
            "isDeleted": false
        ]
        let docRef = ref.collection("storages").document(storage.id.uuidString)
        do {
            try await docRef.setData(data, merge: true)
        } catch {
            print("Firestore: Failed to sync storage '\(storage.name)' — \(error.localizedDescription)")
            AnalyticsManager.shared.track(.syncFailed(reason: error.localizedDescription))
            if isRetryableSyncError(error) {
                queueWrite(kind: .storage, entityId: storage.id.uuidString)
            }
        }
    }

    // MARK: - Item CRUD

    /// Push an inventory item to Firestore. Debounced — rapid counts on the same item
    /// within 1.5s collapse to a single Firestore write.
    func syncItem(_ item: InventoryItem) {
        let key = item.id.uuidString
        pendingItemTasks[key]?.cancel()
        pendingItemTasks[key] = Task {
            try? await Task.sleep(nanoseconds: debounceDuration)
            guard !Task.isCancelled else { return }
            await pushItem(item)
            pendingItemTasks.removeValue(forKey: key)
        }
    }

    /// Cancel all debounced writes and push current local state immediately.
    /// Called when the app enters background so mid-session counts are not lost.
    func flushPending(storages: [Storage], items: [InventoryItem]) async {
        pendingItemTasks.values.forEach { $0.cancel() }
        pendingStorageTasks.values.forEach { $0.cancel() }
        pendingItemTasks.removeAll()
        pendingStorageTasks.removeAll()

        await pushAllConcurrently(storages: storages, items: items, maxConcurrent: 10)
        await flushPendingWrites(items: items, storages: storages)
    }

    /// Push storages then items with a MainActor task pool (SwiftData models are not
    /// Sendable, so withTaskGroup cannot cross isolation boundaries).
    private func pushAllConcurrently(
        storages: [Storage],
        items: [InventoryItem],
        maxConcurrent: Int
    ) async {
        for storage in storages {
            await pushStorage(storage)
        }
        await pushModelsWithConcurrency(items, maxConcurrent: maxConcurrent) { item in
            await self.pushItem(item)
        }
    }

    private func pushModelsWithConcurrency<T>(
        _ models: [T],
        maxConcurrent: Int,
        operation: @escaping @MainActor (T) async -> Void
    ) async {
        guard !models.isEmpty else { return }
        var inFlight: [Task<Void, Never>] = []
        for model in models {
            while inFlight.count >= maxConcurrent {
                _ = await inFlight.removeFirst().value
            }
            inFlight.append(Task { await operation(model) })
        }
        for task in inFlight {
            await task.value
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
            if item.photoURL != nil {
                self.deleteItemPhoto(itemId: item.id)
            }
        }
    }

    private func pushItem(_ item: InventoryItem) async {
        guard let ref = try? userRef() else { return }
        guard let storageID = item.storage?.id.uuidString else {
            print("Firestore: Item '\(item.name)' has no storage — skipping sync.")
            return
        }
        var data: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "itemDescription": item.itemDescription,
            "sku": item.sku,
            "barcode": item.barcode,
            "currentQuantity": item.currentQuantity,
            "minQuantity": item.minQuantity,
            "maxQuantity": item.maxQuantity,
            "unitCost": item.unitCost,
            "reorderPercentage": item.reorderPercentage,
            "lastPurchasePrice": item.lastPurchasePrice,
            "isOutOfStock": item.currentQuantity <= 0,
            "category": item.category,
            "uomName": item.uom?.name ?? "",
            "uomSymbol": item.uom?.symbol ?? "",
            "uomCategory": item.uom?.category ?? "",
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": Timestamp(date: item.updatedAt),
            "isDeleted": false
        ]
        if let exp = item.expiryDate {
            data["expiryDate"] = Timestamp(date: exp)
        } else {
            data["expiryDate"] = NSNull()
        }
        if let url = item.photoURL {
            data["photoURL"] = url
        } else {
            data["photoURL"] = NSNull()
        }
        if let tid = item.createdFromTemplateId {
            data["createdFromTemplateId"] = tid.uuidString
        } else {
            data["createdFromTemplateId"] = NSNull()
        }
        if let purchasedAt = item.lastPurchasedAt {
            data["lastPurchasedAt"] = Timestamp(date: purchasedAt)
        } else {
            data["lastPurchasedAt"] = NSNull()
        }
        let docRef = ref
            .collection("storages").document(storageID)
            .collection("items").document(item.id.uuidString)
        do {
            try await docRef.setData(data, merge: true)
        } catch {
            print("Firestore: Failed to sync item '\(item.name)' — \(error.localizedDescription)")
            AnalyticsManager.shared.track(.syncFailed(reason: error.localizedDescription))
            if isRetryableSyncError(error) {
                queueWrite(kind: .item, entityId: item.id.uuidString)
            }
        }
    }

    // MARK: - Item Templates

    func syncTemplate(_ template: ItemTemplate) {
        Task {
            guard let ref = try? userRef() else { return }
            let data: [String: Any] = [
                "id": template.id.uuidString,
                "name": template.name,
                "templateDescription": template.templateDescription,
                "category": template.category,
                "uomSymbol": template.uomSymbol,
                "uomName": template.uomName,
                "defaultMinQty": template.defaultMinQty,
                "defaultMaxQty": template.defaultMaxQty,
                "createdAt": Timestamp(date: template.createdAt),
                "isDeleted": false
            ]
            let docRef = ref.collection("itemTemplates").document(template.id.uuidString)
            try? await docRef.setData(data, merge: true)
        }
    }

    func deleteTemplate(_ template: ItemTemplate) {
        Task {
            guard let ref = try? userRef() else { return }
            let docRef = ref.collection("itemTemplates").document(template.id.uuidString)
            try? await docRef.updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
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

    func syncActivity(_ event: ActivityEvent) {
        guard let ref = try? userRef() else { return }
        let activityRef = ref.collection("activity").document(event.id.uuidString)
        var data: [String: Any] = [
            "eventType": event.eventType,
            "itemName": event.itemName,
            "storageName": event.storageName,
            "notes": event.notes,
            "occurredAt": Timestamp(date: event.occurredAt)
        ]
        if let before = event.quantityBefore { data["quantityBefore"] = before }
        if let after = event.quantityAfter { data["quantityAfter"] = after }
        if let performer = event.performedBy { data["performedBy"] = performer }
        activityRef.setData(data, merge: true) { error in
            if let error {
                print("syncActivity failed: \(error.localizedDescription)")
            }
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
                        found.supplierEmail = d["supplierEmail"] as? String ?? ""
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
                    newStorage.supplierEmail = d["supplierEmail"] as? String ?? ""
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

            let uid = ref.documentID

            let templateSnapshot = try await ref.collection("itemTemplates")
                .whereField("isDeleted", isEqualTo: false)
                .getDocuments()

            for templateDoc in templateSnapshot.documents {
                let d = templateDoc.data()
                guard let idString = d["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let name = d["name"] as? String else { continue }

                let existing = (try? modelContext.fetch(
                    FetchDescriptor<ItemTemplate>(
                        predicate: #Predicate { $0.id == id }
                    )
                )) ?? []
                guard existing.isEmpty else { continue }

                let template = ItemTemplate(
                    name: name,
                    description: d["templateDescription"] as? String ?? "",
                    category: d["category"] as? String ?? "Uncategorised",
                    uomSymbol: d["uomSymbol"] as? String ?? "pcs",
                    uomName: d["uomName"] as? String ?? "Pieces",
                    defaultMinQty: d["defaultMinQty"] as? Double ?? 0,
                    defaultMaxQty: d["defaultMaxQty"] as? Double ?? 0
                )
                template.id = id
                if let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() {
                    template.createdAt = createdAt
                }
                modelContext.insert(template)
            }

            // Pull last 50 activity events
            let activitySnap = try await db
                .collection("users").document(uid)
                .collection("activity")
                .order(by: "occurredAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            for doc in activitySnap.documents {
                let d = doc.data()
                guard let typeStr = d["eventType"] as? String,
                      let itemName = d["itemName"] as? String,
                      let storageName = d["storageName"] as? String,
                      let ts = d["occurredAt"] as? Timestamp else { continue }

                let docId = UUID(uuidString: doc.documentID) ?? UUID()

                let existing = (try? modelContext.fetch(
                    FetchDescriptor<ActivityEvent>(
                        predicate: #Predicate { $0.id == docId }
                    )
                )) ?? []
                guard existing.isEmpty else { continue }

                let event = ActivityEvent(
                    eventType: typeStr,
                    itemName: itemName,
                    storageName: storageName,
                    quantityBefore: d["quantityBefore"] as? Double,
                    quantityAfter: d["quantityAfter"] as? Double,
                    notes: d["notes"] as? String ?? "",
                    performedBy: d["performedBy"] as? String
                )
                event.id = docId
                event.occurredAt = ts.dateValue()
                modelContext.insert(event)
            }
            modelContext.safeSave(context: "pullFromCloud activity events")

            modelContext.safeSave(context: "pullFromCloud")
            syncState = .success
            lastSyncDate = Date()

            let allStorages = (try? modelContext.fetch(FetchDescriptor<Storage>())) ?? []
            let allItems = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
            await flushPendingWrites(items: allItems, storages: allStorages)

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

        await pushAllConcurrently(storages: storages, items: items, maxConcurrent: 10)

        syncState = .success
        lastSyncDate = Date()
        print("Firestore ✅ Full push complete — \(storages.count) storages, \(items.count) items.")
    }

    // MARK: - Offline Write Queue

    private func loadPendingWrites() -> [PendingWrite] {
        guard let data = UserDefaults.standard.data(forKey: pendingWritesKey),
              let writes = try? JSONDecoder().decode([PendingWrite].self, from: data)
        else { return [] }
        return writes
    }

    private func savePendingWrites(_ writes: [PendingWrite]) {
        guard let data = try? JSONEncoder().encode(writes) else { return }
        UserDefaults.standard.set(data, forKey: pendingWritesKey)
    }

    private func queueWrite(kind: PendingWrite.Kind, entityId: String) {
        var writes = loadPendingWrites()
        writes.removeAll { $0.entityId == entityId && $0.kind == kind }
        writes.append(PendingWrite(id: UUID(), kind: kind, entityId: entityId, queuedAt: Date()))
        savePendingWrites(writes)
    }

    func flushPendingWrites(items: [InventoryItem], storages: [Storage]) async {
        let writes = loadPendingWrites()
        guard !writes.isEmpty else { return }
        var remaining = writes
        for write in writes {
            switch write.kind {
            case .item:
                if let item = items.first(where: { $0.id.uuidString == write.entityId }) {
                    do {
                        try await pushItemThrowing(item)
                        remaining.removeAll { $0.id == write.id }
                    } catch {
                        if !isRetryableSyncError(error) {
                            remaining.removeAll { $0.id == write.id }
                        }
                    }
                } else {
                    remaining.removeAll { $0.id == write.id }
                }
            case .storage:
                if let storage = storages.first(where: { $0.id.uuidString == write.entityId }) {
                    do {
                        try await pushStorageThrowing(storage)
                        remaining.removeAll { $0.id == write.id }
                    } catch {
                        if !isRetryableSyncError(error) {
                            remaining.removeAll { $0.id == write.id }
                        }
                    }
                } else {
                    remaining.removeAll { $0.id == write.id }
                }
            }
        }
        savePendingWrites(remaining)
    }

    private func isRetryableSyncError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return true }
        if ns.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: ns.code) {
            case .unavailable, .deadlineExceeded, .resourceExhausted, .aborted, .internal:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func pushStorageThrowing(_ storage: Storage) async throws {
        guard let ref = try? userRef() else { return }
        let data: [String: Any] = [
            "id": storage.id.uuidString,
            "name": storage.name,
            "location": storage.location,
            "storageDescription": storage.storageDescription,
            "color": storage.color,
            "supplierEmail": storage.supplierEmail,
            "createdAt": Timestamp(date: storage.createdAt),
            "updatedAt": Timestamp(date: storage.updatedAt),
            "isDeleted": false
        ]
        let docRef = ref.collection("storages").document(storage.id.uuidString)
        try await docRef.setData(data, merge: true)
    }

    private func pushItemThrowing(_ item: InventoryItem) async throws {
        guard let ref = try? userRef() else { return }
        guard let storageID = item.storage?.id.uuidString else { return }
        var data: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "itemDescription": item.itemDescription,
            "sku": item.sku,
            "barcode": item.barcode,
            "currentQuantity": item.currentQuantity,
            "minQuantity": item.minQuantity,
            "maxQuantity": item.maxQuantity,
            "unitCost": item.unitCost,
            "reorderPercentage": item.reorderPercentage,
            "lastPurchasePrice": item.lastPurchasePrice,
            "isOutOfStock": item.currentQuantity <= 0,
            "category": item.category,
            "uomName": item.uom?.name ?? "",
            "uomSymbol": item.uom?.symbol ?? "",
            "uomCategory": item.uom?.category ?? "",
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": Timestamp(date: item.updatedAt),
            "isDeleted": false
        ]
        if let exp = item.expiryDate {
            data["expiryDate"] = Timestamp(date: exp)
        } else {
            data["expiryDate"] = NSNull()
        }
        if let url = item.photoURL {
            data["photoURL"] = url
        } else {
            data["photoURL"] = NSNull()
        }
        if let tid = item.createdFromTemplateId {
            data["createdFromTemplateId"] = tid.uuidString
        } else {
            data["createdFromTemplateId"] = NSNull()
        }
        if let purchasedAt = item.lastPurchasedAt {
            data["lastPurchasedAt"] = Timestamp(date: purchasedAt)
        } else {
            data["lastPurchasedAt"] = NSNull()
        }
        let docRef = ref
            .collection("storages").document(storageID)
            .collection("items").document(item.id.uuidString)
        try await docRef.setData(data, merge: true)
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
                found.reorderPercentage = data["reorderPercentage"] as? Double ?? 0
                found.lastPurchasePrice = data["lastPurchasePrice"] as? Double ?? 0
                if let ts = data["lastPurchasedAt"] as? Timestamp {
                    found.lastPurchasedAt = ts.dateValue()
                } else {
                    found.lastPurchasedAt = nil
                }
                found.category = data["category"] as? String ?? "Uncategorised"
                found.uom = resolveUOM(
                    symbol: (data["uomSymbol"] as? String) ?? (data["uom"] as? String),
                    name: data["uomName"] as? String,
                    category: data["uomCategory"] as? String,
                    in: modelContext
                )
                if let ts = data["expiryDate"] as? Timestamp {
                    found.expiryDate = ts.dateValue()
                } else {
                    found.expiryDate = nil
                }
                found.photoURL = data["photoURL"] as? String
                if let tidString = data["createdFromTemplateId"] as? String {
                    found.createdFromTemplateId = UUID(uuidString: tidString)
                }
                // isOutOfStock from Firestore is ignored — derived from currentQuantity locally
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
                category: data["category"] as? String ?? "Uncategorised",
                expiryDate: (data["expiryDate"] as? Timestamp).map { $0.dateValue() },
                storage: storage
            )
            newItem.id = id
            newItem.uom = resolveUOM(
                symbol: (data["uomSymbol"] as? String) ?? (data["uom"] as? String),
                name: data["uomName"] as? String,
                category: data["uomCategory"] as? String,
                in: modelContext
            )
            if let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() {
                newItem.createdAt = createdAt
            }
            newItem.photoURL = data["photoURL"] as? String
            newItem.reorderPercentage = data["reorderPercentage"] as? Double ?? 0
            newItem.lastPurchasePrice = data["lastPurchasePrice"] as? Double ?? 0
            if let ts = data["lastPurchasedAt"] as? Timestamp {
                newItem.lastPurchasedAt = ts.dateValue()
            }
            if let tidString = data["createdFromTemplateId"] as? String {
                newItem.createdFromTemplateId = UUID(uuidString: tidString)
            }
            modelContext.insert(newItem)
        }
    }

    private func resolveUOM(
        symbol: String?,
        name: String?,
        category: String?,
        in modelContext: ModelContext
    ) -> UOM? {
        guard let rawSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSymbol.isEmpty else {
            return nil
        }

        let descriptor = FetchDescriptor<UOM>(
            predicate: #Predicate { $0.symbol == rawSymbol }
        )
        if let found = try? modelContext.fetch(descriptor).first {
            return found
        }

        let cleanedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = cleanedName.isEmpty ? rawSymbol : cleanedName
        let resolvedCategory = cleanedCategory.isEmpty ? "Count" : cleanedCategory
        let newUOM = UOM(name: resolvedName, symbol: rawSymbol, category: resolvedCategory)
        modelContext.insert(newUOM)
        return newUOM
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
