import SwiftUI
import SwiftData

struct QuickSaleSheet: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var quantityText: String = "1"
    @State private var showingSmartSales = false
    @State private var sellingPriceText: String = ""
    @State private var priceWasEdited = false
    @State private var saleDate: Date = Date()
    @State private var showDatePicker: Bool = false
    @State private var showNotes: Bool = false
    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showNegativeStockAlert = false
    @State private var negativeStockAlertMessage = ""
    @State private var didTrackSaleEntryStarted = false
    @State private var saleEntryOpenedAt = Date()
    @State private var didEmitSaleTerminal = false
    @State private var didCompleteSmartSales = false

    private var qty: Double { Double(quantityText) ?? 0 }
    private var price: Double { Double(sellingPriceText) ?? 0 }
    private var unitPrice: Double { priceWasEdited ? price : (price > 0 ? price : item.fallbackSalePrice) }
    private var revenue: Double { qty * unitPrice }
    private var cost: Double { qty * item.unitCost }
    private var profit: Double { revenue - cost }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // TODO(iOS-C1): when Manual Purchase Entry ships, add a matching
                    // Smart Purchase chip ("Or scan an invoice with Smart Purchase →")
                    // on that screen using AIEntryChip(feature: .smartPurchase).
                    AIEntryChip(feature: .smartSales, screen: "sales_manual") {
                        emitSaleAbandonedIfNeeded(stage: "switched_to_smart_sales")
                        didCompleteSmartSales = false
                        showingSmartSales = true
                    }
                    itemInfoSection
                    quantitySection
                    sellingPriceSection
                    if unitPrice > 0 && qty > 0 {
                        saleTotalSection
                    }
                    dateSection
                    if unitPrice > 0 {
                        profitPreview
                    }
                    notesSection

                    Button("Record Sale") { saveSale() }
                        .buttonStyle(.borderedProminent)
                        .tint(.stoqlyAccent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(qty <= 0 || isSaving)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("quickSaleRecordButton")
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Record Sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        emitSaleAbandonedIfNeeded()
                        dismiss()
                    }
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
                if isSaving {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                    }
                }
            }
        }
        .sheet(isPresented: $showingSmartSales, onDismiss: {
            if didCompleteSmartSales {
                dismiss()
            } else if didEmitSaleTerminal {
                beginManualSaleSession()
            }
        }) {
            SmartSalesEntryView(onCompleted: {
                didCompleteSmartSales = true
            })
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
        .onAppear {
            if !didTrackSaleEntryStarted {
                beginManualSaleSession()
            }
            if item.sellingPrice > 0 {
                sellingPriceText = String(format: "%.2f", item.sellingPrice)
            } else if item.fallbackSalePrice > 0 {
                sellingPriceText = String(format: "%.2f", item.fallbackSalePrice)
            }
        }
        .onDisappear {
            guard !showingSmartSales else { return }
            emitSaleAbandonedIfNeeded()
        }
        .alert(
            L("sale.negativeStock.title", "Negative Stock"),
            isPresented: $showNegativeStockAlert
        ) {
            Button(L("OK", "OK"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(negativeStockAlertMessage)
        }
    }

    private var itemInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.title2)
                .fontWeight(.bold)
            Text(item.storage?.name ?? "Unknown")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("In Stock: \(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "units")  ·  SKU: \(item.sku)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUANTITY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack {
                Button {
                    let current = Double(quantityText) ?? 1
                    quantityText = max(0, current - 1).smartFormatted
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                TextField("1", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("quickSaleQuantityField")
                Button {
                    let current = Double(quantityText) ?? 0
                    quantityText = (current + 1).smartFormatted
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
            Text(item.uom?.symbol ?? "units")
                .font(.caption2)
                .foregroundColor(.secondary)
            if qty > item.currentQuantity {
                Text("Selling more than in stock (have: \(item.currentQuantity.smartFormatted)). Sale will record a negative stock.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var sellingPriceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("sale.pricePerUnit.label", "Price/unit").uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack {
                Text(currencyManager.selectedCurrency.symbol)
                TextField("0.00", text: $sellingPriceText)
                    .keyboardType(.decimalPad)
                    .onChange(of: sellingPriceText) { _, _ in
                        priceWasEdited = true
                    }
                    .accessibilityIdentifier("quickSalePriceField")
            }
            if item.sellingPrice > 0,
               sellingPriceText.isEmpty || abs((Double(sellingPriceText) ?? 0) - item.sellingPrice) > 0.001 {
                Button("Use default price (\(currencyManager.formatPrice(item.sellingPrice)))") {
                    sellingPriceText = String(format: "%.2f", item.sellingPrice)
                    priceWasEdited = false
                }
                .font(.caption)
            } else if item.sellingPrice == 0, item.fallbackSalePrice > 0, !priceWasEdited {
                Button("Use fallback price (\(currencyManager.formatPrice(item.fallbackSalePrice)))") {
                    sellingPriceText = String(format: "%.2f", item.fallbackSalePrice)
                    priceWasEdited = false
                }
                .font(.caption)
            }
            if item.sellingPrice == 0 {
                Text(L("sale.noSellingPrice.warning", "Selling price not set. Set selling price for better profit insights."))
                .font(.caption)
                .foregroundColor(.orange)
            }
            if unitPrice > 0 && qty > 0 {
                Text("= \(currencyManager.formatPrice(revenue))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var saleTotalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("sale.total.label", "Sale Total"))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(currencyManager.formatPrice(revenue))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.stoqlyPrimary)
                .accessibilityIdentifier("quickSaleSaleTotal")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Button {
                showDatePicker.toggle()
            } label: {
                Text(saleDate.formatted(date: .abbreviated, time: .omitted))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showDatePicker {
                DatePicker("", selection: $saleDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
        }
    }

    private var profitPreview: some View {
        let hasCost = item.unitCost > 0
        let margin = (hasCost && revenue > 0) ? profit / revenue * 100 : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Revenue: \(currencyManager.formatPrice(revenue))")
            if hasCost {
                Text("Profit: \(currencyManager.formatPrice(profit))")
                Text("Margin: \(String(format: "%.0f", margin))%")
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Set unit cost in item details to see profit margin")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.12))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasCost
            ? "Revenue \(currencyManager.formatPrice(revenue)), Profit \(currencyManager.formatPrice(profit)), Margin \(String(format: "%.0f", margin)) percent"
            : "Revenue \(currencyManager.formatPrice(revenue)). No unit cost set."
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showNotes.toggle()
            } label: {
                Text("NOTES (optional)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            if showNotes {
                TextField("Notes", text: $notes)
            }
        }
    }

    private func saveSale() {
        guard !isSaving else { return }
        isSaving = true

        let soldQty = qty
        let resolvedPrice = unitPrice
        let unitCost = item.unitCost
        let storageName = item.storage?.name ?? "Unknown"

        let event = ActivityEvent(
            eventType: "SaleMade",
            itemName: item.name,
            storageName: storageName,
            quantityBefore: item.currentQuantity,
            quantityAfter: item.currentQuantity - soldQty,
            notes: "Sale: \(soldQty.smartFormatted) @ \(currencyManager.formatPrice(resolvedPrice))"
        )
        modelContext.insert(event)

        let sale = SaleEvent(
            item: item,
            itemName: item.name,
            itemSKU: item.sku,
            storageName: storageName,
            category: item.category,
            quantitySold: soldQty,
            pricePerUnit: resolvedPrice,
            costPerUnit: unitCost,
            notes: notes,
            occurredAt: saleDate
        )
        modelContext.insert(sale)

        let movement = InventoryMovement(
            item: item,
            itemName: item.name,
            itemSKU: item.sku,
            storageName: storageName,
            category: item.category,
            direction: "OUT",
            movementType: MovementTypeOut.saleOut.rawValue,
            quantity: soldQty,
            pricePerUnit: resolvedPrice,
            notes: "Quick Sale",
            occurredAt: saleDate,
            linkedSaleEventId: sale.id
        )
        modelContext.insert(movement)

        item.currentQuantity -= soldQty
        item.updatedAt = Date()

        guard modelContext.safeSave(context: "QuickSaleSheet") else {
            modelContext.rollback()
            isSaving = false
            return
        }

        didEmitSaleTerminal = true
        AnalyticsManager.shared.track(
            .saleEntryCompleted(
                mode: "manual",
                itemCount: 1,
                durationMs: max(0, Int(Date().timeIntervalSince(saleEntryOpenedAt) * 1_000))
            )
        )

        Task {
            await FirestoreManager.shared.pushSaleEvent(sale)
            await FirestoreManager.shared.pushInventoryMovement(movement)
            FirestoreManager.shared.syncItem(item)
        }

        AnalyticsManager.shared.track(.saleRecorded(
            itemId: item.id.uuidString,
            qty: soldQty,
            sellingPrice: resolvedPrice,
            costPrice: unitCost,
            profit: (resolvedPrice - unitCost) * soldQty,
            storageId: item.storage?.id.uuidString ?? "",
            mode: "manual"
        ))

        isSaving = false

        let negativeLines = SaleHelpers.negativeStockMessages(for: [item])
        if negativeLines.isEmpty {
            dismiss()
        } else {
            negativeStockAlertMessage = negativeLines.joined(separator: "\n")
            showNegativeStockAlert = true
        }
    }

    private func beginManualSaleSession() {
        didTrackSaleEntryStarted = true
        didEmitSaleTerminal = false
        saleEntryOpenedAt = Date()
        AnalyticsManager.shared.track(.saleEntryStarted(mode: "manual"))
    }

    private func emitSaleAbandonedIfNeeded(stage: String = "cancelled") {
        guard didTrackSaleEntryStarted, !didEmitSaleTerminal else { return }
        didEmitSaleTerminal = true
        AnalyticsManager.shared.track(.saleEntryAbandoned(mode: "manual", stage: stage))
        AnalyticsManager.shared.track(.saleEntryCancelled(mode: "manual"))
    }
}
