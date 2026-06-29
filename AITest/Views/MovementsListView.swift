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
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func movementRow(_ movement: InventoryMovement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movement.isIN ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(movement.isIN ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(movement.movementType) · \(movement.quantity.smartFormatted)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(movement.itemName) · \(movement.occurredAt.formatted(date: .abbreviated, time: .shortened))")
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
