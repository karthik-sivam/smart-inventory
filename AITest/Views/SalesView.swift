import SwiftUI
import SwiftData

struct SalesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @Query(sort: \SaleEvent.occurredAt, order: .reverse) private var allSales: [SaleEvent]

    @State private var showingItemPicker = false
    @State private var showingSmartSales = false
    @State private var showingReports = false
    @State private var showingQuickSale = false
    @State private var preselectedItem: InventoryItem?
    @State private var savedSaleCount = 0
    @State private var showSavedToast = false
    @State private var reverseToastMessage: String?
    @State private var salePendingReverse: SaleEvent?
    @State private var showSwipeReverseConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if allSales.isEmpty { emptyState }
                else { salesList }
            }
            .navigationTitle("Sales")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .overlay(alignment: .top) {
                if showSavedToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("\(savedSaleCount) sale\(savedSaleCount == 1 ? "" : "s") saved")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: showSavedToast)
                }
            }
        }
        .sheet(isPresented: $showingItemPicker) {
            SaleItemPickerSheet { item in
                preselectedItem = item
                showingItemPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    showingQuickSale = true
                }
            }
            .sheetStyle()
        }
        .sheet(isPresented: $showingQuickSale) {
            if let item = preselectedItem {
                QuickSaleSheet(item: item)
                    .environmentObject(currencyManager)
                    .sheetStyle()
            }
        }
        .sheet(isPresented: $showingSmartSales) {
            SmartSalesEntryView()
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingReports) {
            ReportsView()
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("stoqly.smartSalesConfirmed"))) { note in
            savedSaleCount = note.userInfo?["count"] as? Int ?? 0
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showSavedToast = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("stoqly.recordSaleFromReports"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingItemPicker = true
            }
        }
        .toast(message: $reverseToastMessage)
        .alert(
            L("sale.reverse.confirm.title", "Reverse this sale?"),
            isPresented: $showSwipeReverseConfirm,
            presenting: salePendingReverse
        ) { sale in
            Button(L("Cancel", "Cancel"), role: .cancel) {
                salePendingReverse = nil
            }
            Button(L("Delete / Reverse", "Delete / Reverse"), role: .destructive) {
                performReverse(sale)
                salePendingReverse = nil
            }
        } message: { _ in
            Text(L("sale.reverse.confirm.message", "The stock will be added back to inventory."))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !allSales.isEmpty {
                    Button { showingSmartSales = true } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(.stoqlyAccent)
                    }
                    .accessibilityIdentifier("smartSalesEntryToolbarButton")
                }
                Button { showingReports = true } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(.stoqlyPrimary)
                }
                .accessibilityIdentifier("salesViewReportsButton")
                if !allSales.isEmpty {
                    Button { showingItemPicker = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("salesAddButton")
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 60)
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.stoqlyPrimary.opacity(0.3))
                Text("No sales yet")
                    .font(.title3).fontWeight(.semibold)
                Text("Record a sale to start tracking your revenue and profit.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Record a Sale") { showingItemPicker = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.stoqlyAccent)
                    .controlSize(.large)
                    .accessibilityIdentifier("salesEmptyRecordButton")
                Button {
                    showingSmartSales = true
                } label: {
                    Label("Smart Sales Entry", systemImage: "sparkles")
                        .foregroundColor(.stoqlyPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("salesEmptySmartEntryButton")
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Sales list (grouped by date)

    private var salesList: some View {
        List {
            ForEach(groupedSales, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sales, id: \.id) { sale in
                        NavigationLink {
                            SaleDetailView(sale: sale) {
                                reverseToastMessage = L("sale.reversed.toast", "Sale reversed")
                            }
                            .environmentObject(currencyManager)
                        } label: {
                            SaleEventRow(sale: sale)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if EditPolicy.isWithinEditWindow(createdAt: sale.createdAt) {
                                Button(role: .destructive) {
                                    salePendingReverse = sale
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

    // MARK: - Grouping logic

    private var groupedSales: [(title: String, sales: [SaleEvent])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var buckets: [String: [SaleEvent]] = [:]
        for sale in allSales {
            let day = cal.startOfDay(for: sale.occurredAt)
            let label: String
            if day == today { label = "Today" }
            else if day == yesterday { label = "Yesterday" }
            else { label = sale.occurredAt.formatted(date: .abbreviated, time: .omitted) }
            buckets[label, default: []].append(sale)
        }
        let priority = ["Today", "Yesterday"]
        let sorted = buckets.keys.sorted { a, b in
            let ai = priority.firstIndex(of: a) ?? Int.max
            let bi = priority.firstIndex(of: b) ?? Int.max
            if ai != bi { return ai < bi }
            return a > b
        }
        return sorted.map { (title: $0, sales: buckets[$0]!) }
    }

    private func performReverse(_ sale: SaleEvent) {
        let result = SaleHelpers.reverseSale(sale, modelContext: modelContext)
        guard result == .success else { return }
        reverseToastMessage = L("sale.reversed.toast", "Sale reversed")
    }
}

// MARK: - SaleEventRow

struct SaleEventRow: View {
    let sale: SaleEvent
    @EnvironmentObject var currencyManager: CurrencyManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.callout).foregroundColor(.stoqlyPrimary)
                .frame(width: 32, height: 32)
                .background(Color.stoqlyPrimary.opacity(0.12))
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.itemName).font(.subheadline).fontWeight(.medium)
                Text("\(sale.quantitySold.smartFormatted) sold")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(currencyManager.formatPrice(sale.revenue))
                    .font(.subheadline).fontWeight(.semibold)
                if sale.pricePerUnit > 0 && sale.costPerUnit > 0 {
                    Text(currencyManager.formatPrice(sale.grossProfit))
                        .font(.caption2)
                        .foregroundColor(sale.grossProfit >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
