import SwiftUI
import SwiftData

struct MovementsListView: View {
    let movements: [InventoryMovement]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var reverseToastMessage: String?
    @State private var movementPendingReverse: InventoryMovement?
    @State private var showSwipeReverseConfirm = false

    private var grouped: [(Date, [InventoryMovement])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: movements) { cal.startOfDay(for: $0.occurredAt) }
        return groups.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
    }

    var body: some View {
        Group {
            if movements.isEmpty {
                ContentUnavailableView {
                    Label("No Movements", systemImage: "arrow.up.arrow.down.circle")
                } description: {
                    Text("Movements recorded from Item Detail will appear here.")
                }
                .onAppear {
                    AnalyticsManager.shared.track(.emptyStateShown(screen: "movements"))
                }
            } else {
                List {
                    ForEach(grouped, id: \.0) { day, dayMovements in
                        Section(header: Text(sectionTitle(for: day))) {
                            ForEach(dayMovements, id: \.id) { movement in
                                NavigationLink {
                                    MovementDetailView(movement: movement) {
                                        reverseToastMessage = L("movement.reversed.toast", "Movement reversed")
                                    }
                                    .environmentObject(currencyManager)
                                } label: {
                                    movementRow(movement)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if movement.linkedSaleEventId == nil,
                                       EditPolicy.isWithinEditWindow(createdAt: movement.createdAt) {
                                        Button(role: .destructive) {
                                            movementPendingReverse = movement
                                            showSwipeReverseConfirm = true
                                        } label: {
                                            Label(
                                                L("Delete / Reverse", "Delete / Reverse"),
                                                systemImage: "arrow.uturn.backward.circle"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Movements")
        .toast(message: $reverseToastMessage)
        .alert(
            L("movement.reverse.confirm.title", "Reverse this movement?"),
            isPresented: $showSwipeReverseConfirm,
            presenting: movementPendingReverse
        ) { movement in
            Button(L("Cancel", "Cancel"), role: .cancel) {
                movementPendingReverse = nil
            }
            Button(L("Delete / Reverse", "Delete / Reverse"), role: .destructive) {
                performReverse(movement)
                movementPendingReverse = nil
            }
        } message: { _ in
            Text(L("movement.reverse.confirm.message", "Stock will be adjusted to undo this movement."))
        }
    }

    private func sectionTitle(for date: Date) -> String {
        AppLocaleFormatting.sectionDayTitle(for: date)
    }

    private func movementRow(_ movement: InventoryMovement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movement.isIN ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(movement.isIN ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    String(
                        format: L("%@ · %@", "%@ · %@"),
                        movement.localizedMovementTypeLabel,
                        movement.quantity.smartFormatted
                    )
                )
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(
                    String(
                        format: L("%@ · %@", "%@ · %@"),
                        movement.itemName,
                        AppLocaleFormatting.abbreviatedDateTime(movement.occurredAt)
                    )
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if movement.pricePerUnit > 0 {
                Text(currencyManager.formatPrice(movement.totalValue))
                    .font(.subheadline)
            }
            if movement.linkedSaleEventId != nil {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func performReverse(_ movement: InventoryMovement) {
        let result = SaleHelpers.reverseMovement(movement, modelContext: modelContext)
        guard result == .success else { return }
        reverseToastMessage = L("movement.reversed.toast", "Movement reversed")
    }
}
