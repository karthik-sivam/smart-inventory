import SwiftUI

struct MovementsListView: View {
    let movements: [InventoryMovement]
    @EnvironmentObject var currencyManager: CurrencyManager

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
            } else {
                List {
                    ForEach(grouped, id: \.0) { day, dayMovements in
                        Section(header: Text(sectionTitle(for: day))) {
                            ForEach(dayMovements, id: \.id) { movement in
                                movementRow(movement)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Movements")
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
                        format: String(
                            localized: "%@ · %@",
                            defaultValue: "%@ · %@"
                        ),
                        movement.localizedMovementTypeLabel,
                        movement.quantity.smartFormatted
                    )
                )
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(
                    String(
                        format: String(
                            localized: "%@ · %@",
                            defaultValue: "%@ · %@"
                        ),
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
        }
    }
}
