import SwiftUI
import SwiftData

// MARK: - Sale detail

struct SaleDetailView: View {
    let sale: SaleEvent
    var onReversed: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var showDeleteConfirm = false

    private var isEditable: Bool {
        EditPolicy.isWithinEditWindow(createdAt: sale.createdAt)
    }

    var body: some View {
        List {
            Section {
                detailRow(
                    L("Item", "Item"),
                    sale.itemName
                )
                detailRow(
                    L("Storage", "Storage"),
                    sale.storageName
                )
                detailRow(
                    L("Quantity", "Quantity"),
                    sale.quantitySold.smartFormatted
                )
                detailRow(
                    L("Price per unit", "Price per unit"),
                    currencyManager.formatPrice(sale.pricePerUnit)
                )
                detailRow(
                    L("Revenue", "Revenue"),
                    currencyManager.formatPrice(sale.revenue)
                )
                if sale.costPerUnit > 0 {
                    detailRow(
                        L("Gross profit", "Gross profit"),
                        currencyManager.formatPrice(sale.grossProfit)
                    )
                }
                detailRow(
                    L("Date", "Date"),
                    AppLocaleFormatting.abbreviatedDateTime(sale.occurredAt)
                )
                if !sale.notes.isEmpty {
                    detailRow(
                        L("Notes", "Notes"),
                        sale.notes
                    )
                }
            }

            Section {
                if isEditable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(
                            L("sale.deleteReverse", "Delete / Reverse"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                    }
                    .accessibilityIdentifier("saleDeleteReverseButton")
                } else {
                    Label {
                        Text(L("edit.locked.note", "Locked — entered more than 7 days ago"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(L("Sale Details", "Sale Details"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L("sale.reverse.confirm.title", "Reverse this sale?"),
            isPresented: $showDeleteConfirm
        ) {
            Button(L("Cancel", "Cancel"), role: .cancel) {}
            Button(L("Delete / Reverse", "Delete / Reverse"), role: .destructive) {
                reverseSale()
            }
        } message: {
            Text(L("sale.reverse.confirm.message", "The stock will be added back to inventory."))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func reverseSale() {
        let result = SaleHelpers.reverseSale(sale, modelContext: modelContext)
        guard result == .success else { return }
        onReversed?()
        dismiss()
    }
}

// MARK: - Movement detail

struct MovementDetailView: View {
    let movement: InventoryMovement
    var onReversed: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var showDeleteConfirm = false

    private var isLinkedToSale: Bool {
        movement.linkedSaleEventId != nil
    }

    private var isEditable: Bool {
        EditPolicy.isWithinEditWindow(createdAt: movement.createdAt) && !isLinkedToSale
    }

    var body: some View {
        List {
            Section {
                detailRow(
                    L("Type", "Type"),
                    movement.localizedMovementTypeLabel
                )
                detailRow(
                    L("Direction", "Direction"),
                    movement.isIN
                        ? L("IN", "IN")
                        : L("OUT", "OUT")
                )
                detailRow(
                    L("Item", "Item"),
                    movement.itemName
                )
                detailRow(
                    L("Storage", "Storage"),
                    movement.storageName
                )
                detailRow(
                    L("Quantity", "Quantity"),
                    movement.quantity.smartFormatted
                )
                if movement.pricePerUnit > 0 {
                    detailRow(
                        L("Value", "Value"),
                        currencyManager.formatPrice(movement.totalValue)
                    )
                }
                detailRow(
                    L("Date", "Date"),
                    AppLocaleFormatting.abbreviatedDateTime(movement.occurredAt)
                )
                if !movement.notes.isEmpty {
                    detailRow(
                        L("Notes", "Notes"),
                        movement.notes
                    )
                }
            }

            Section {
                if isLinkedToSale {
                    Label {
                        Text(L("movement.linkedToSale.note", "Part of a sale — edit from the Sales list."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "link.circle")
                            .foregroundColor(.secondary)
                    }
                } else if isEditable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(
                            L("sale.deleteReverse", "Delete / Reverse"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                    }
                    .accessibilityIdentifier("movementDeleteReverseButton")
                } else {
                    Label {
                        Text(L("edit.locked.note", "Locked — entered more than 7 days ago"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(L("Movement Details", "Movement Details"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L("movement.reverse.confirm.title", "Reverse this movement?"),
            isPresented: $showDeleteConfirm
        ) {
            Button(L("Cancel", "Cancel"), role: .cancel) {}
            Button(L("Delete / Reverse", "Delete / Reverse"), role: .destructive) {
                reverseMovement()
            }
        } message: {
            Text(L("movement.reverse.confirm.message", "Stock will be adjusted to undo this movement."))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func reverseMovement() {
        let result = SaleHelpers.reverseMovement(movement, modelContext: modelContext)
        guard result == .success else { return }
        onReversed?()
        dismiss()
    }
}
