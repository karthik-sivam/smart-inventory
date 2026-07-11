import SwiftUI
import SwiftData

struct SaleEntryReviewView: View {
    @Binding var rows: [ParsedSaleRow]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query private var allItems: [InventoryItem]

    @State private var isSaving = false
    @State private var pickingItemRowID: UUID?

    private var confirmableRows: [ParsedSaleRow] { rows.filter { !$0.isSkipped } }
    private var unresolvedCount: Int { confirmableRows.filter { $0.resolvedItem == nil }.count }

    var body: some View {
        VStack(spacing: 0) {
            if unresolvedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("\(unresolvedCount) item\(unresolvedCount == 1 ? "" : "s") not matched to inventory")
                        .font(.caption).fontWeight(.medium)
                    Spacer()
                    Text("Tap row to link").font(.caption2).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
                .padding([.horizontal, .top])
            }

            List {
                ForEach(rows) { row in
                    SaleReviewRow(
                        row: row,
                        currencyManager: currencyManager,
                        itemName: fieldBinding(row.id, \.itemName),
                        quantitySold: fieldBinding(row.id, \.quantitySold),
                        pricePerUnit: fieldBinding(row.id, \.pricePerUnit),
                        isSkipped: fieldBinding(row.id, \.isSkipped),
                        onRequestItemPicker: { pickingItemRowID = row.id }
                    )
                }
                .onDelete { rows.remove(atOffsets: $0) }
            }
            .listStyle(.plain)

            Divider()
            VStack(spacing: 10) {
                if unresolvedCount > 0 {
                    Text("\(unresolvedCount) unresolved item\(unresolvedCount == 1 ? "" : "s") will still be saved — stock will not be deducted until linked.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }
                Button(isSaving ? "Saving…" : "Confirm \(confirmableRows.count) Sale\(confirmableRows.count == 1 ? "" : "s")") {
                    Task { await saveAllSales() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.stoqlyAccent)
                .controlSize(.large)
                .disabled(isSaving || confirmableRows.isEmpty)
                .padding(.horizontal)
                Button("Cancel") { onCancel() }
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Review Sales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onCancel() }
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
        .onAppear { autoResolveRows() }
        .onChange(of: allItems) { _, _ in autoResolveRows() }
    }

    private func fieldBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<ParsedSaleRow, T>) -> Binding<T> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? ParsedSaleRow.defaultValue(for: keyPath) },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func linkItem(id: UUID, to item: InventoryItem) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].resolvedItem = item
    }

    private func autoResolveRows() {
        for index in rows.indices where rows[index].resolvedItem == nil {
            let query = rows[index].itemName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            if let exact = allItems.first(where: { $0.name.lowercased() == query }) {
                rows[index].resolvedItem = exact
                continue
            }

            guard query.count >= 3 else { continue }
            let candidates = allItems.filter {
                $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
            }
            if candidates.count == 1 {
                rows[index].resolvedItem = candidates.first
            }
        }
    }

    private func saveAllSales() async {
        isSaving = true
        let now = Date()
        var savedSales: [SaleEvent] = []
        var savedMovements: [InventoryMovement] = []
        var updatedItems: [InventoryItem] = []

        for row in confirmableRows {
            let unitCost = row.resolvedItem?.unitCost ?? 0
            let storageName = row.resolvedItem?.storage?.name ?? ""
            let category = row.resolvedItem?.category ?? ""

            let event = ActivityEvent(
                eventType: "SaleMade",
                itemName: row.itemName,
                storageName: storageName,
                notes: "Smart Sales Entry batch"
            )
            modelContext.insert(event)
            FirestoreManager.shared.syncActivity(event)

            let sale = SaleEvent(
                item: row.resolvedItem,
                itemName: row.resolvedItem?.name ?? row.itemName,
                itemSKU: row.resolvedItem?.sku ?? "",
                storageName: storageName,
                category: category,
                quantitySold: row.quantitySold,
                pricePerUnit: row.pricePerUnit,
                costPerUnit: unitCost,
                notes: row.notes,
                occurredAt: now
            )
            modelContext.insert(sale)
            savedSales.append(sale)

            if let item = row.resolvedItem {
                let movement = InventoryMovement(
                    item: item,
                    itemName: item.name,
                    itemSKU: item.sku,
                    storageName: storageName,
                    category: item.category,
                    direction: "OUT",
                    movementType: MovementTypeOut.saleOut.rawValue,
                    quantity: row.quantitySold,
                    pricePerUnit: row.pricePerUnit,
                    notes: "Smart Sales Entry",
                    occurredAt: now,
                    linkedSaleEventId: sale.id
                )
                modelContext.insert(movement)
                savedMovements.append(movement)
                item.currentQuantity -= row.quantitySold
                item.updatedAt = now
                updatedItems.append(item)
            }
        }

        modelContext.safeSave(context: "SmartSalesEntryBatch")

        Task {
            for sale in savedSales {
                await FirestoreManager.shared.pushSaleEvent(sale)
            }
            for movement in savedMovements {
                await FirestoreManager.shared.pushInventoryMovement(movement)
            }
            for item in updatedItems {
                FirestoreManager.shared.syncItem(item)
            }
        }

        AnalyticsManager.shared.track(.smartSalesCompleted(mode: "batch", saleCount: confirmableRows.count))

        isSaving = false
        let savedCount = confirmableRows.count
        onConfirm()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("stoqly.smartSalesConfirmed"),
                object: nil,
                userInfo: ["count": savedCount]
            )
        }
    }
}

// MARK: - SaleReviewRow

struct SaleReviewRow: View {
    let row: ParsedSaleRow
    let currencyManager: CurrencyManager
    @Binding var itemName: String
    @Binding var quantitySold: Double
    @Binding var pricePerUnit: Double
    @Binding var isSkipped: Bool
    let onRequestItemPicker: () -> Void

    private var isUnresolved: Bool { row.resolvedItem == nil && !isSkipped }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isUnresolved { Circle().fill(Color.orange).frame(width: 8, height: 8) }
                TextField("Item name", text: $itemName).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button(isSkipped ? "Undo skip" : "Skip") { isSkipped.toggle() }
                    .font(.caption2).foregroundColor(.secondary)
                    .buttonStyle(.borderless)
            }
            if !isSkipped {
                if let linked = row.resolvedItem {
                    HStack(spacing: 8) {
                        Text("→ \(linked.name)").font(.caption2).fontWeight(.medium).foregroundColor(.stoqlyPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.stoqlyPrimary.opacity(0.1)).cornerRadius(10)
                        Button("Change") { onRequestItemPicker() }
                            .font(.caption2).foregroundColor(.secondary)
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                    if let storageName = linked.storage?.name, !storageName.isEmpty {
                        Text(storageName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Link to inventory item →") { onRequestItemPicker() }
                            .font(.caption2).foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1)).cornerRadius(10)
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                }
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Qty").font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $quantitySold, format: .number).font(.caption)
                            .keyboardType(.decimalPad).frame(width: 60)
                        if let uomSymbol = row.resolvedItem?.uom?.symbol, !uomSymbol.isEmpty {
                            Text(uomSymbol).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(currencyManager.selectedCurrency.symbol).font(.caption).foregroundColor(.secondary)
                        TextField("0.00", value: $pricePerUnit, format: .number).font(.caption)
                            .keyboardType(.decimalPad).frame(width: 70)
                        if pricePerUnit == 0 {
                            Text("(no price)").font(.caption2).foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    if pricePerUnit > 0 && quantitySold > 0 {
                        Text(currencyManager.formatPrice(quantitySold * pricePerUnit))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.stoqlyPrimary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isSkipped ? 0.4 : 1.0)
    }
}

private extension ParsedSaleRow {
    static func defaultValue<T>(for keyPath: WritableKeyPath<ParsedSaleRow, T>) -> T {
        ParsedSaleRow(itemName: "", quantitySold: 0, pricePerUnit: 0)[keyPath: keyPath]
    }
}
