import SwiftUI
import SwiftData

struct SaleEntryReviewView: View {
    @Binding var rows: [ParsedSaleRow]
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query private var allItems: [InventoryItem]

    @State private var isSaving = false
    @State private var pickingItemRowID: UUID?
    @State private var showNegativeStockAlert = false
    @State private var negativeStockAlertMessage = ""
    @State private var pendingConfirmCount = 0
    @State private var isAutoAcceptedExpanded = false
    @State private var isReviewAllDetected = false
    @State private var manualReviewIDs: Set<UUID> = []
    @State private var reviewResolutions: [UUID: SmartReviewResolution] = [:]
    @State private var startedWithOnlyAutoAccepted = false
    @State private var didInitializeReview = false

    private var autoAcceptedRows: [ParsedSaleRow] {
        rows.filter {
            !$0.isSkipped && $0.confidence >= SmartCountConfig.autoAcceptThreshold && !manualReviewIDs.contains($0.id)
        }
    }

    private var rowsNeedingReview: [ParsedSaleRow] {
        rows.filter {
            $0.confidence < SmartCountConfig.autoAcceptThreshold || manualReviewIDs.contains($0.id)
        }
    }

    private var acceptedRows: [ParsedSaleRow] {
        rows.filter { row in
            guard !row.isSkipped else { return false }
            if row.confidence >= SmartCountConfig.autoAcceptThreshold,
               !manualReviewIDs.contains(row.id) {
                return true
            }
            return reviewResolution(for: row) == .confirmed
        }
    }

    private var allReviewRowsResolved: Bool {
        rowsNeedingReview.allSatisfy {
            let resolution = reviewResolution(for: $0)
            return resolution == .confirmed || resolution == .dismissed
        }
    }

    private var unresolvedCount: Int { acceptedRows.filter { $0.resolvedItem == nil }.count }

    private var saleTotal: Double {
        acceptedRows.reduce(0) { $0 + ($1.quantitySold * $1.pricePerUnit) }
    }

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
                if isReviewAllDetected {
                    Section("All detected items") {
                        ForEach(rows) { row in
                            smartSalesReviewRow(row)
                        }
                    }
                } else {
                    Section {
                        Button {
                            withAnimation { isAutoAcceptedExpanded.toggle() }
                        } label: {
                            HStack {
                                Label(
                                    "\(autoAcceptedRows.count) items auto-accepted",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundColor(.green)
                                Spacer()
                                Image(systemName: isAutoAcceptedExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("smartSalesAutoAcceptedSection")

                        if isAutoAcceptedExpanded {
                            ForEach(autoAcceptedRows) { row in
                                SmartAutoAcceptedRow(
                                    name: row.itemName,
                                    quantity: row.quantitySold,
                                    unitSymbol: row.resolvedItem?.uom?.symbol,
                                    confidence: row.confidence,
                                    onEdit: { moveToReview(row.id) }
                                )
                            }
                        }
                    }

                    Section("Needs review") {
                        if rowsNeedingReview.isEmpty {
                            Label("No items need review", systemImage: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            ForEach(rowsNeedingReview) { row in
                                smartSalesReviewRow(row)
                            }
                        }
                    }
                }

                Section {
                    Button("Review all detected items") {
                        isReviewAllDetected = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("smartSalesReviewAllLink")
                }
            }
            .listStyle(.insetGrouped)

            Divider()
            VStack(spacing: 10) {
                if saleTotal > 0 {
                    VStack(spacing: 4) {
                        Text(L("sale.total.label", "Sale Total"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currencyManager.formatPrice(saleTotal))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.stoqlyPrimary)
                            .accessibilityIdentifier("saleReviewSaleTotal")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }

                if unresolvedCount > 0 {
                    Text("\(unresolvedCount) unresolved item\(unresolvedCount == 1 ? "" : "s") will still be saved — stock will not be deducted until linked.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }
                if !rowsNeedingReview.isEmpty && !allReviewRowsResolved && !autoAcceptedRows.isEmpty {
                    Button("Save auto-accepted only") {
                        chooseOnlyAutoAcceptedRows()
                        Task { await saveAllSales() }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Button(isSaving ? "Saving…" : saveButtonTitle) {
                    Task { await saveAllSales() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.stoqlyAccent)
                .controlSize(.large)
                .disabled(isSaving || acceptedRows.isEmpty || !allReviewRowsResolved)
                .padding(.horizontal)
                .accessibilityIdentifier("smartSalesReviewSaveButton")
                Button("Cancel") { onCancel() }
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Review Sales")
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
        .alert(
            L("sale.negativeStock.title", "Negative Stock"),
            isPresented: $showNegativeStockAlert
        ) {
            Button(L("OK", "OK"), role: .cancel) {
                finishConfirm(count: pendingConfirmCount)
            }
        } message: {
            Text(negativeStockAlertMessage)
        }
        .onAppear {
            initializeReviewIfNeeded()
            autoResolveRows()
        }
        .onChange(of: allItems) { _, _ in autoResolveRows() }
    }

    private var saveButtonTitle: String {
        let count = acceptedRows.count
        if startedWithOnlyAutoAccepted && rowsNeedingReview.isEmpty {
            return "Save \(count) auto-accepted items"
        }
        return "Save \(count) items"
    }

    @ViewBuilder
    private func smartSalesReviewRow(_ row: ParsedSaleRow) -> some View {
        let resolution = reviewResolution(for: row)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if resolution == .confirmed {
                    Label("Confirmed", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if resolution == .dismissed {
                    Label("Dismissed", systemImage: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            SaleReviewRow(
                row: row,
                currencyManager: currencyManager,
                itemName: fieldBinding(row.id, \.itemName),
                quantitySold: fieldBinding(row.id, \.quantitySold),
                pricePerUnit: fieldBinding(row.id, \.pricePerUnit),
                priceWasEdited: fieldBinding(row.id, \.priceWasEdited),
                onRequestItemPicker: { pickingItemRowID = row.id }
            )
            .disabled(resolution == .dismissed)
            .opacity(resolution == .dismissed ? 0.45 : 1)

            SmartReviewActionBar(
                resolution: resolution,
                onConfirm: { confirmReview(row.id) },
                onEdit: { moveToReview(row.id) },
                onDismiss: { toggleDismissed(row.id) }
            )
        }
        .accessibilityIdentifier("smartSalesReviewRow_\(row.itemName)")
    }

    private func initializeReviewIfNeeded() {
        guard !didInitializeReview else { return }
        didInitializeReview = true
        startedWithOnlyAutoAccepted = rows.allSatisfy {
            $0.confidence >= SmartCountConfig.autoAcceptThreshold
        }
    }

    private func reviewResolution(for row: ParsedSaleRow) -> SmartReviewResolution {
        if row.isSkipped { return .dismissed }
        return reviewResolutions[row.id] ?? .pending
    }

    private func moveToReview(_ id: UUID) {
        manualReviewIDs.insert(id)
        reviewResolutions[id] = .pending
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].isSkipped = false
        }
    }

    private func confirmReview(_ id: UUID) {
        manualReviewIDs.insert(id)
        reviewResolutions[id] = .confirmed
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].isSkipped = false
        }
    }

    private func toggleDismissed(_ id: UUID) {
        manualReviewIDs.insert(id)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isSkipped.toggle()
        reviewResolutions[id] = rows[index].isSkipped ? .dismissed : .pending
    }

    private func chooseOnlyAutoAcceptedRows() {
        for row in rowsNeedingReview {
            guard let index = rows.firstIndex(where: { $0.id == row.id }) else { continue }
            rows[index].isSkipped = true
            reviewResolutions[row.id] = .dismissed
        }
    }

    private func fieldBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<ParsedSaleRow, T>) -> Binding<T> {
        Binding(
            get: { rows.first(where: { $0.id == id })?[keyPath: keyPath] ?? ParsedSaleRow.defaultValue(for: keyPath) },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index][keyPath: keyPath] = newValue
                moveToReview(id)
            }
        )
    }

    private func linkItem(id: UUID, to item: InventoryItem) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].resolvedItem = item
        moveToReview(id)
        if !rows[index].priceWasEdited && rows[index].pricePerUnit == 0 {
            SaleHelpers.applyFallbackPriceIfNeeded(&rows[index], from: item)
        }
    }

    private func autoResolveRows() {
        for index in rows.indices where rows[index].resolvedItem == nil {
            let query = rows[index].itemName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }

            if let exact = allItems.first(where: { $0.name.lowercased() == query }) {
                rows[index].resolvedItem = exact
                if !rows[index].priceWasEdited && rows[index].pricePerUnit == 0 {
                    SaleHelpers.applyFallbackPriceIfNeeded(&rows[index], from: exact)
                }
                continue
            }

            guard query.count >= 3 else { continue }
            let candidates = allItems.filter {
                $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
            }
            if candidates.count == 1, let match = candidates.first {
                rows[index].resolvedItem = match
                if !rows[index].priceWasEdited && rows[index].pricePerUnit == 0 {
                    SaleHelpers.applyFallbackPriceIfNeeded(&rows[index], from: match)
                }
            }
        }
    }

    private func saveAllSales() async {
        isSaving = true
        let rowsToSave = acceptedRows
        guard !rowsToSave.isEmpty else {
            isSaving = false
            return
        }
        let now = Date()
        var savedSales: [SaleEvent] = []
        var savedMovements: [InventoryMovement] = []
        var updatedItems: [InventoryItem] = []

        for row in rowsToSave {
            let unitCost = row.resolvedItem?.unitCost ?? 0
            let storageName = row.resolvedItem?.storage?.name ?? ""
            let category = row.resolvedItem?.category ?? ""

            let stockBefore = row.resolvedItem?.currentQuantity ?? 0
            let event = ActivityEvent(
                eventType: "SaleMade",
                itemName: row.itemName,
                storageName: storageName,
                quantityBefore: stockBefore,
                quantityAfter: stockBefore - row.quantitySold,
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

        guard modelContext.safeSave(context: "SmartSalesAccept") else {
            modelContext.rollback()
            isSaving = false
            return
        }

        // TODO(iOS-B2): fire smart_sales_review_completed{auto_accepted,
        //               user_confirmed, duration_ms, entry_source} via
        //               AmplitudeManager helper.

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

        AnalyticsManager.shared.track(.smartSalesCompleted(mode: "batch", saleCount: rowsToSave.count))

        isSaving = false
        let savedCount = rowsToSave.count
        let negativeLines = SaleHelpers.negativeStockMessages(for: updatedItems)
        if negativeLines.isEmpty {
            finishConfirm(count: savedCount)
        } else {
            negativeStockAlertMessage = negativeLines.joined(separator: "\n")
            pendingConfirmCount = savedCount
            showNegativeStockAlert = true
        }
    }

    private func finishConfirm(count: Int) {
        onConfirm(count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("stoqly.smartSalesConfirmed"),
                object: nil,
                userInfo: ["count": count]
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
    @Binding var priceWasEdited: Bool
    let onRequestItemPicker: () -> Void

    private var isUnresolved: Bool { row.resolvedItem == nil && !row.isSkipped }

    private var lineValue: Double { quantitySold * pricePerUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isUnresolved { Circle().fill(Color.orange).frame(width: 8, height: 8) }
                SmartConfidenceChip(confidence: row.confidence)
                TextField("Item name", text: $itemName).font(.subheadline).fontWeight(.medium)
                Spacer()
            }
            if !row.isSkipped {
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
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Qty").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            TextField("0", text: Binding(
                                get: { quantitySold.smartFormatted },
                                set: { quantitySold = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                            ))
                                .font(.caption)
                                .keyboardType(.decimalPad).frame(width: 60)
                            if let uomSymbol = row.resolvedItem?.uom?.symbol, !uomSymbol.isEmpty {
                                Text(uomSymbol).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("sale.pricePerUnit.label", "Price/unit"))
                            .font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(currencyManager.selectedCurrency.symbol).font(.caption).foregroundColor(.secondary)
                            TextField("0.00", value: $pricePerUnit, format: .number).font(.caption)
                                .keyboardType(.decimalPad).frame(width: 70)
                                .onChange(of: pricePerUnit) { _, _ in
                                    priceWasEdited = true
                                }
                        }
                        if row.resolvedItem?.sellingPrice == 0 {
                            Text(L("sale.noSellingPrice.warning", "Selling price not set. Set selling price for better profit insights."))
                            .font(.caption2)
                            .foregroundColor(.orange)
                        }
                        if lineValue > 0 {
                            Text("= \(currencyManager.formatPrice(lineValue))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(row.isSkipped ? 0.4 : 1.0)
    }
}

private extension ParsedSaleRow {
    static func defaultValue<T>(for keyPath: WritableKeyPath<ParsedSaleRow, T>) -> T {
        ParsedSaleRow(itemName: "", quantitySold: 0, pricePerUnit: 0, confidence: 0.4)[keyPath: keyPath]
    }
}
