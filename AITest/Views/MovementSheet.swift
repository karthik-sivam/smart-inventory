import SwiftUI
import SwiftData

struct MovementSheet: View {
    let item: InventoryItem
    var onOpenQuickSale: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var direction: String = "IN"
    @State private var movementTypeIn: MovementTypeIn = .purchase
    @State private var movementTypeOut: MovementTypeOut = .waste
    @State private var quantityText: String = ""
    @State private var pricePerUnitText: String = ""
    @State private var movementDate: Date = Date()
    @State private var notes: String = ""
    @State private var showDatePicker: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    directionSection
                    typeSection
                    quantitySection
                    priceSection
                    dateSection
                    TextField("Notes (optional)", text: $notes)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Add Movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveMovement() }
                        .disabled(quantityText.isEmpty || (Double(quantityText) ?? 0) == 0 || isSaving)
                }
            }
        }
        .onChange(of: direction) { _, _ in updatePriceDefault() }
        .onChange(of: movementTypeIn) { _, _ in updatePriceDefault() }
        .onChange(of: movementTypeOut) { _, _ in updatePriceDefault() }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIRECTION")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Picker("Direction", selection: $direction) {
                Text("IN").tag("IN")
                Text("OUT").tag("OUT")
            }
            .pickerStyle(.segmented)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TYPE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            if direction == "IN" {
                Picker("Type", selection: $movementTypeIn) {
                    ForEach(MovementTypeIn.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Type", selection: $movementTypeOut) {
                    ForEach(MovementTypeOut.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                if movementTypeOut == .saleOut {
                    Text("Tap Add to open Quick Sale instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUANTITY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack {
                TextField("0", text: $quantityText)
                    .keyboardType(.decimalPad)
                Text(item.uom?.symbol ?? "units")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(priceSectionTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            TextField("0.00", text: $pricePerUnitText)
                .keyboardType(.decimalPad)
        }
    }

    private var priceSectionTitle: String {
        if direction == "IN" && movementTypeIn == .purchase {
            return "Purchase Price per Unit"
        }
        if direction == "OUT" && movementTypeOut == .waste {
            return "Wasted Value per Unit"
        }
        return "Price per Unit (optional)"
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
                Text(movementDate.formatted(date: .abbreviated, time: .omitted))
            }
            if showDatePicker {
                DatePicker("", selection: $movementDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
        }
    }

    private func updatePriceDefault() {
        switch (direction, movementTypeIn, movementTypeOut) {
        case ("IN", .purchase, _), ("OUT", _, .waste):
            if item.unitCost > 0 {
                pricePerUnitText = String(format: "%.2f", item.unitCost)
            }
        default:
            break
        }
    }

    private func saveMovement() {
        if direction == "OUT" && movementTypeOut == .saleOut {
            dismiss()
            onOpenQuickSale?()
            return
        }

        guard !isSaving else { return }
        isSaving = true

        let qty = Double(quantityText) ?? 0
        let price = Double(pricePerUnitText) ?? 0
        let storageName = item.storage?.name ?? "Unknown"
        let movType = direction == "IN" ? movementTypeIn.rawValue : movementTypeOut.rawValue

        let qBefore = item.currentQuantity
        let qAfter = direction == "IN" ? qBefore + qty : qBefore - qty

        let event = ActivityEvent(
            eventType: "MovementLogged",
            itemName: item.name,
            storageName: storageName,
            quantityBefore: qBefore,
            quantityAfter: qAfter,
            notes: "\(direction) \(movType): \(qty.smartFormatted)"
        )
        modelContext.insert(event)

        let movement = InventoryMovement(
            item: item,
            itemName: item.name,
            itemSKU: item.sku,
            storageName: storageName,
            category: item.category,
            direction: direction,
            movementType: movType,
            quantity: qty,
            pricePerUnit: price,
            notes: notes,
            occurredAt: movementDate
        )
        modelContext.insert(movement)

        if direction == "IN" {
            item.currentQuantity += qty
        } else {
            item.currentQuantity -= qty
        }
        item.updatedAt = Date()
        modelContext.safeSave(context: "MovementSheet")

        Task {
            await FirestoreManager.shared.pushInventoryMovement(movement)
            FirestoreManager.shared.syncItem(item)
        }

        AnalyticsManager.shared.track(.movementLogged(
            itemId: item.id.uuidString,
            movementType: movType,
            qty: qty,
            pricePerUnit: price
        ))

        isSaving = false
        dismiss()
    }
}
