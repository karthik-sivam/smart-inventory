import SwiftUI
import SwiftData

struct PurchaseReviewView: View {
    @Binding var rows: [ParsedPurchaseRow]
    let defaultStorage: Storage?
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    @Query(sort: \Storage.name) private var allStorages: [Storage]

    @State private var isSaving = false
    @State private var validationError: String?
    @State private var pickingItemRowID: UUID?
    @State private var pickingStorageRowID: UUID?

    private var catalogItems: [InventoryItem] {
        if let defaultStorage { return defaultStorage.items }
        return allItems
    }

    private var confirmableRows: [ParsedPurchaseRow] { rows.filter { !$0.isSkipped } }
    private var unresolvedCount: Int { confirmableRows.filter { $0.resolvedItem == nil }.count }
    private var rowsMissingStorage: [ParsedPurchaseRow] {
        confirmableRows.filter { $0.resolvedItem == nil && $0.targetStorage == nil && defaultStorage == nil }
    }

    var body: some View {
        reviewContent
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { pickingItemRowID != nil },
                set: { if !$0 { pickingItemRowID = nil } }
            )) {
                if let rowID = pickingItemRowID {
                    SaleItemPickerSheet { item in
                        linkItem(id: rowID, to: item)
                    }
                    .sheetStyle()
                }
            }
            .sheet(isPresented: Binding(
                get: { pickingStorageRowID != nil },
                set: { if !$0 { pickingStorageRowID = nil } }
            )) {
                NavigationStack {
                    List(allStorages) { storage in
                        Button(storage.name) {
                            assignStorage(id: pickingStorageRowID, to: storage)
                            pickingStorageRowID = nil
                        }
                    }
                    .navigationTitle("Pick Storage")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { pickingStorageRowID = nil }
                        }
                    }
                }
                .sheetStyle()
            }
            .onAppear { autoResolveRows() }
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            unresolvedBanner
            validationBanner
            rowsList
            confirmButton
        }
    }

    @ViewBuilder
    private var unresolvedBanner: some View {
        if unresolvedCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(unresolvedBannerText)
                    .font(.caption).fontWeight(.medium)
                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
            .padding([.horizontal, .top])
        }
    }

    private var unresolvedBannerText: String {
        let suffix = unresolvedCount == 1 ? "" : "s"
        if let name = defaultStorage?.name {
            return "\(unresolvedCount) item\(suffix) not matched in \(name)"
        }
        return "\(unresolvedCount) item\(suffix) not matched to inventory"
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let validationError {
            Text(validationError)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }

    private var rowsList: some View {
        List {
            ForEach(rows) { row in
                PurchaseReviewRow(
                    row: row,
                    defaultStorage: defaultStorage,
                    currencyManager: currencyManager,
                    itemName: fieldBinding(row.id, \.itemName),
                    quantityReceived: fieldBinding(row.id, \.quantityReceived),
                    costPerUnit: fieldBinding(row.id, \.costPerUnit),
                    isSkipped: fieldBinding(row.id, \.isSkipped),
                    onRequestItemPicker: { pickingItemRowID = row.id },
                    onRequestStoragePicker: { pickingStorageRowID = row.id }
                )
            }
            .onDelete { rows.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
    }

    private var confirmButton: some View {
        let label = isSaving
            ? "Saving…"
            : "Confirm \(confirmableRows.count) Item\(confirmableRows.count == 1 ? "" : "s")"
        return Button(label) {
            Task { await saveAllPurchases() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.stoqlyAccent)
        .controlSize(.large)
        .disabled(isSaving || confirmableRows.isEmpty || !rowsMissingStorage.isEmpty)
        .padding()
    }

    private func assignStorage(id: UUID?, to storage: Storage) {
        guard let id, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].targetStorage = storage
    }

    private func fieldBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<ParsedPurchaseRow, T>) -> Binding<T> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? ParsedPurchaseRow.defaultValue(for: keyPath) },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func linkItem(id: UUID, to item: InventoryItem) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].resolvedItem = item
        rows[index].targetStorage = item.storage
    }

    private func autoResolveRows() {
        for index in rows.indices where rows[index].resolvedItem == nil {
            let query = rows[index].itemName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            if let exact = catalogItems.first(where: { $0.name.lowercased() == query }) {
                rows[index].resolvedItem = exact
                rows[index].targetStorage = exact.storage
                continue
            }

            guard query.count >= 3 else { continue }
            let candidates = catalogItems.filter {
                $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
            }
            if candidates.count == 1, let matched = candidates.first {
                rows[index].resolvedItem = matched
                rows[index].targetStorage = matched.storage
            } else if rows[index].resolvedItem == nil, rows[index].targetStorage == nil, let defaultStorage {
                rows[index].targetStorage = defaultStorage
            }
        }
    }

    private func saveAllPurchases() async {
        validationError = nil

        if !rowsMissingStorage.isEmpty {
            validationError = "Assign a storage to continue"
            return
        }

        let unmatched = confirmableRows.filter { $0.resolvedItem == nil }
        if !unmatched.isEmpty {
            validationError = "Link unmatched items to inventory items first, or skip them."
            return
        }

        isSaving = true
        let now = Date()
        var savedMovements: [InventoryMovement] = []
        var updatedItems: [InventoryItem] = []

        for row in confirmableRows {
            guard let item = row.resolvedItem else { continue }
            let movStorage = row.targetStorage ?? item.storage ?? defaultStorage
            guard let movStorage else { continue }
            let storageName = movStorage.name

            // Capture stock before/after so the activity feed shows "+N" instead of a generic line.
            let qBefore = item.currentQuantity
            let qAfter = qBefore + row.quantityReceived

            let event = ActivityEvent(
                eventType: "MovementLogged",
                itemName: item.name,
                storageName: storageName,
                quantityBefore: qBefore,
                quantityAfter: qAfter,
                notes: "Purchase invoice import"
            )
            modelContext.insert(event)
            FirestoreManager.shared.syncActivity(event)

            let movement = InventoryMovement(
                item: item,
                itemName: item.name,
                itemSKU: item.sku,
                storageName: storageName,
                category: item.category,
                direction: "IN",
                movementType: MovementTypeIn.purchase.rawValue,
                quantity: row.quantityReceived,
                pricePerUnit: row.costPerUnit,
                notes: row.notes.isEmpty ? "Invoice import" : row.notes,
                occurredAt: now
            )
            modelContext.insert(movement)
            savedMovements.append(movement)

            item.currentQuantity = qAfter
            if row.costPerUnit > 0 {
                item.lastPurchasePrice = row.costPerUnit
                item.lastPurchasedAt = now
            }
            item.updatedAt = now
            updatedItems.append(item)
        }

        guard !updatedItems.isEmpty else {
            isSaving = false
            validationError = "Link unmatched items to inventory items first, or skip them."
            return
        }

        guard modelContext.safeSave(context: "PurchaseInvoiceImport") else {
            modelContext.rollback()
            isSaving = false
            return
        }

        Task {
            for movement in savedMovements {
                await FirestoreManager.shared.pushInventoryMovement(movement)
            }
            for item in updatedItems {
                FirestoreManager.shared.syncItem(item)
            }
        }

        isSaving = false
        let savedCount = confirmableRows.count
        let savedItemCount = updatedItems.count
        onConfirm(savedItemCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("stoqly.purchaseInvoiceConfirmed"),
                object: nil,
                userInfo: ["count": savedCount, "itemCount": savedItemCount]
            )
        }
    }
}

struct PurchaseReviewRow: View {
    let row: ParsedPurchaseRow
    let defaultStorage: Storage?
    let currencyManager: CurrencyManager
    @Binding var itemName: String
    @Binding var quantityReceived: Double
    @Binding var costPerUnit: Double
    @Binding var isSkipped: Bool
    let onRequestItemPicker: () -> Void
    let onRequestStoragePicker: () -> Void

    private var storageLabel: String? {
        row.targetStorage?.name ?? row.resolvedItem?.storage?.name ?? defaultStorage?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            nameRow
            if !isSkipped {
                linkSection
                quantityCostRow
            }
        }
        .padding(.vertical, 4)
        .opacity(isSkipped ? 0.4 : 1.0)
    }

    private var nameRow: some View {
        HStack {
            TextField("Item name", text: $itemName).font(.subheadline).fontWeight(.medium)
            Button(isSkipped ? "Undo skip" : "Skip") { isSkipped.toggle() }
                .font(.caption2).foregroundColor(.secondary)
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var linkSection: some View {
        if let linked = row.resolvedItem {
            Text("→ \(linked.name)").font(.caption2).foregroundColor(.stoqlyPrimary)
            if let name = storageLabel {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Button("Change item") { onRequestItemPicker() }
                .font(.caption2).foregroundColor(.secondary)
                .buttonStyle(.borderless)
        } else {
            Button("Link to item →") { onRequestItemPicker() }
                .font(.caption2).foregroundColor(.orange)
                .buttonStyle(.borderless)
            storageAssignmentRow
        }
    }

    @ViewBuilder
    private var storageAssignmentRow: some View {
        if let name = row.targetStorage?.name {
            storagePill("→ \(name)", highlighted: true)
        } else if let defaultStorage {
            storagePill("→ \(defaultStorage.name)", highlighted: false)
        } else {
            Button("Pick storage →") { onRequestStoragePicker() }
                .font(.caption2).foregroundColor(.orange)
                .buttonStyle(.borderless)
        }
    }

    private func storagePill(_ name: String, highlighted: Bool) -> some View {
        Text(name)
            .font(.caption2)
            .foregroundColor(highlighted ? .stoqlyPrimary : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(highlighted ? Color.stoqlyPrimary.opacity(0.1) : Color(.systemGray5))
            .cornerRadius(10)
    }

    private var quantityCostRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("Qty").font(.caption).foregroundColor(.secondary)
                TextField("0", value: $quantityReceived, format: .number)
                    .keyboardType(.decimalPad).frame(width: 60)
                if let uomSymbol = row.resolvedItem?.uom?.symbol, !uomSymbol.isEmpty {
                    Text(uomSymbol).font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                Text(currencyManager.selectedCurrency.symbol).font(.caption).foregroundColor(.secondary)
                TextField("0.00", value: $costPerUnit, format: .number)
                    .keyboardType(.decimalPad).frame(width: 70)
            }
        }
    }
}

private extension ParsedPurchaseRow {
    static func defaultValue<T>(for keyPath: WritableKeyPath<ParsedPurchaseRow, T>) -> T {
        ParsedPurchaseRow(itemName: "", quantityReceived: 0, costPerUnit: 0)[keyPath: keyPath]
    }
}
