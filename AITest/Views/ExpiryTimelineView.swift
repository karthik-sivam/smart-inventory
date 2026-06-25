import SwiftUI

// MARK: - Expiry Timeline View
//
// Groups items with expiry dates into urgency tiers and shows a visual
// days-remaining bar for each item. Replaces the generic FilteredItemListView
// for the "Expiring Soon" Dashboard card.

struct ExpiryTimelineView: View {

    let items: [InventoryItem]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: InventoryItem? = nil

    // MARK: - Urgency tiers

    enum Tier: String, CaseIterable {
        case expired     = "Expired"
        case critical    = "Critical"    // 1–3 days
        case soon        = "Expiring Soon" // 4–7 days
        case upcoming    = "Upcoming"    // 8–30 days

        var color: Color {
            switch self {
            case .expired:  return .red
            case .critical: return .red
            case .soon:     return .orange
            case .upcoming: return .yellow
            }
        }

        var icon: String {
            switch self {
            case .expired:  return "xmark.circle.fill"
            case .critical: return "exclamationmark.triangle.fill"
            case .soon:     return "clock.badge.exclamationmark"
            case .upcoming: return "calendar.badge.exclamationmark"
            }
        }
    }

    private func tier(for item: InventoryItem) -> Tier? {
        // Use `nearestExpiryDate` so items with batches surface at the urgency
        // of their soonest-expiring batch; items without batches still fall
        // back to their stored `expiryDate`.
        guard let expiry = item.nearestExpiryDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if expiry < Date()      { return .expired }
        if days <= 3            { return .critical }
        if days <= 7            { return .soon }
        if days <= 30           { return .upcoming }
        return nil // > 30 days — not shown
    }

    private var groupedItems: [(Tier, [InventoryItem])] {
        var buckets: [Tier: [InventoryItem]] = [:]
        for item in items {
            guard let t = tier(for: item) else { continue }
            buckets[t, default: []].append(item)
        }
        return Tier.allCases.compactMap { tier in
            guard let group = buckets[tier], !group.isEmpty else { return nil }
            let sorted = group.sorted {
                ($0.nearestExpiryDate ?? .distantFuture) < ($1.nearestExpiryDate ?? .distantFuture)
            }
            return (tier, sorted)
        }
    }

    private var totalCount: Int { groupedItems.reduce(0) { $0 + $1.1.count } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if groupedItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(groupedItems, id: \.0) { tier, tierItems in
                                tierSection(tier: tier, items: tierItems)
                            }
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Expiry Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(totalCount) item\(totalCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onAppear {
                AnalyticsManager.shared.track(.expiryTimelineViewed(itemCount: totalCount))
            }
        }
        .sheet(item: $selectedItem) { item in
            // B6: ItemDetailView no longer wraps itself in a NavigationStack.
            NavigationStack {
                ItemDetailView(item: item)
            }
            .sheetStyle()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("Nothing expiring soon")
                .font(.title3).fontWeight(.medium)
            Text("No items are expiring within the next 30 days.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Tier section

    private func tierSection(tier: Tier, items: [InventoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: tier.icon)
                    .foregroundColor(tier.color)
                    .font(.caption)
                Text(tier.rawValue.uppercased())
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("(\(items.count))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            // Item rows
            VStack(spacing: 1) {
                ForEach(items, id: \.id) { item in
                    ExpiryItemRow(item: item, tier: tier)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Expiry Item Row

private struct ExpiryItemRow: View {
    let item: InventoryItem
    let tier: ExpiryTimelineView.Tier

    private var daysText: String {
        guard let expiry = item.nearestExpiryDate else { return "" }
        if expiry < Date() {
            let days = Calendar.current.dateComponents([.day], from: expiry, to: Date()).day ?? 0
            return days == 0 ? "Expired today" : "Expired \(days)d ago"
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days == 0 { return "Expires today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }

    /// Fraction 0–1 representing urgency (1 = expired/today, 0 = 30 days out)
    private var urgencyFraction: Double {
        guard let expiry = item.nearestExpiryDate else { return 0 }
        if expiry <= Date() { return 1.0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 30
        return max(0, min(1.0, 1.0 - Double(days) / 30.0))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Urgency colour stripe
                RoundedRectangle(cornerRadius: 2)
                    .fill(tier.color)
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.storage?.name ?? "No Storage")
                            .font(.caption2).foregroundColor(.secondary)
                        if item.currentQuantity > 0 {
                            Text("·")
                                .font(.caption2).foregroundColor(.secondary)
                            Text("\(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(daysText)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(tier.color)
                    if let expiry = item.nearestExpiryDate {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Urgency bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 3)
                    Rectangle()
                        .fill(tier.color.opacity(0.7))
                        .frame(width: geo.size.width * urgencyFraction, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 14)

            Divider().padding(.leading, 14)
        }
    }
}
