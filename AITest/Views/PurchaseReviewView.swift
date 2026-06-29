import SwiftUI
import SwiftData

struct PurchaseReviewView: View {
    @Binding var rows: [ParsedPurchaseRow]
    let defaultStorage: Storage
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var isSaving = false

    private var storageItems: [InventoryItem] { defaultStorage.items }
    private var confirmableRows: [ParsedPurchaseRow] { rows.filter { !$0.isSkipped } }
    private var unresolvedCount: Int { confirmableRows.filter { $0.resolvedItem == nil }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if unresolvedCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("\(unresolvedCount) item\(unresolvedCount == 1 ? "" : "s") not matched in \(defaultStorage.name)")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding([.horizontal, .top])
                }

                List {
                    ForEach($rows) { $row in
                        PurchaseReviewRow(row: $row, storageItems: storageItems, currencyManager: currencyManager)
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                }
                .listStyle(.plain)

                Button(isSaving ? "Saving…" : "Confirm \(confirmableRows.count) Item\(confirmableRows.count == 1 ? "" : "s")") {
                    Task { await saveAllPurchases() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.stoqlyAccent)
                .controlSize(.large)
                .disabled(isSaving || confirmableRows.isEmpty)
                .padding()

                Button("Cancel") { onCancel() }
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Review Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .onAppear { autoResolveRows() }
    }

    private func autoResolveRows() {
        for index in rows.indices where rows[index].resolvedItem == nil {
            let query = rows[index].itemName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            if let exact = storageItems.first(where: { $0.name.lowercased() == query }) {
                rows[index].resolvedItem = exact
                continue
            }

            guard query.count >= 3 else { continue }
            let candidates = storageItems.filter {
                $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
            }
            if candidates.count == 1 {
                rows[index].resolvedItem = candidates.first
            }
        }
    }

    private func saveAllPurchases() async {
        isSaving = true
        let now = Date()
        var savedMovements: [InventoryMovement] = []
        var updatedItems: [InventoryItem] = []

        for row in confirmableRows {
            guard let item = row.resolvedItem else { continue }
            let storageName = defaultStorage.name

            let event = ActivityEvent(
                eventType: "MovementLogged",
                itemName: item.name,
                storageName: storageName,
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

            item.currentQuantity += row.quantityReceived
            if row.costPerUnit > 0 {
                item.lastPurchasePrice = row.costPerUnit
                item.lastPurchasedAt = now
            }
            item.updatedAt = now
            updatedItems.append(item)
        }

        modelContext.safeSave(context: "PurchaseInvoiceImport")

        Task {
            for movement in savedMovements {
                await FirestoreManager.shared.pushInventoryMovement(movement)
            }
            for item in updatedItems {
                FirestoreManager.shared.syncItem(item)
            }
        }

        isSaving = false
        onConfirm()
    }
}

struct PurchaseReviewRow: View {
    @Binding var row: ParsedPurchaseRow
    let storageItems: [InventoryItem]
    let currencyManager: CurrencyManager
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: $row.itemName).font(.subheadline).fontWeight(.medium)
                Button(row.isSkipped ? "Undo" : "Skip") { row.isSkipped.toggle() }
                    .font(.caption2).foregroundColor(.secondary)
            }
            if !row.isSkipped {
                if let linked = row.resolvedItem {
                    Text("→ \(linked.name)").font(.caption2).foregroundColor(.stoqlyPrimary)
                } else {
                    Button("Link to item →") { showingPicker = true }
                        .font(.caption2).foregroundColor(.orange)
                }
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Qty").font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $row.quantityReceived, format: .number)
                            .keyboardType(.decimalPad).frame(width: 60)
                    }
                    HStack(spacing: 4) {
                        Text(currencyManager.selectedCurrency.symbol).font(.caption).foregroundColor(.secondary)
                        TextField("0.00", value: $row.costPerUnit, format: .number)
                            .keyboardType(.decimalPad).frame(width: 70)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(row.isSkipped ? 0.4 : 1.0)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                List(storageItems, id: \.id) { item in
                    Button(item.name) {
                        row.resolvedItem = item
                        showingPicker = false
                    }
                }
                .navigationTitle("Select Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingPicker = false }
                    }
                }
            }
            .sheetStyle()
        }
    }
}
