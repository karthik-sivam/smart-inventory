import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Query(sort: \SaleEvent.occurredAt, order: .reverse) private var allSales: [SaleEvent]
    @Query(sort: \InventoryMovement.occurredAt, order: .reverse) private var allMovements: [InventoryMovement]

    enum ReportPeriod: String, CaseIterable {
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30Days = "Last 30 Days"
        case custom = "Custom"
    }

    @State var selectedPeriod: ReportPeriod = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var showingPaywall: Bool = false
    @State private var movementsExpanded: Bool = true

    init(selectedPeriod: ReportPeriod = .thisMonth) {
        _selectedPeriod = State(initialValue: selectedPeriod)
    }

    private var periodRange: ClosedRange<Date> {
        let now = Date()
        let cal = Calendar.current
        switch selectedPeriod {
        case .today:
            return cal.startOfDay(for: now)...now
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return start...now
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return start...now
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return start...now
        case .custom:
            return customStart...customEnd
        }
    }

    private var filteredSales: [SaleEvent] {
        allSales.filter { periodRange.contains($0.occurredAt) }
    }

    private var filteredMovements: [InventoryMovement] {
        allMovements.filter { periodRange.contains($0.occurredAt) }
    }

    private var totalRevenue: Double { filteredSales.reduce(0) { $0 + $1.revenue } }
    private var totalCOGS: Double { filteredSales.reduce(0) { $0 + $1.cogs } }
    private var totalProfit: Double { filteredSales.reduce(0) { $0 + $1.grossProfit } }
    private var totalMarginPct: Double? {
        guard totalRevenue > 0 else { return nil }
        return totalProfit / totalRevenue * 100
    }

    private var dailyRevenue: [DailyRevenue] {
        let cal = Calendar.current
        var map: [Date: Double] = [:]
        for sale in filteredSales {
            let day = cal.startOfDay(for: sale.occurredAt)
            map[day, default: 0] += sale.revenue
        }
        return map.map { DailyRevenue(date: $0.key, revenue: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var allDays: [DailyRevenue] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: periodRange.lowerBound)
        let end = cal.startOfDay(for: periodRange.upperBound)
        var days: [DailyRevenue] = []
        var cursor = start
        while cursor <= end {
            let dayStart = cal.startOfDay(for: cursor)
            let revenue = dailyRevenue.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.revenue ?? 0
            days.append(DailyRevenue(date: dayStart, revenue: revenue))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private var useDayNumberAxis: Bool {
        allDays.count > 7
    }

    private var topItemsByRevenue: [(name: String, qty: Double, revenue: Double)] {
        var map: [String: (qty: Double, revenue: Double)] = [:]
        for sale in filteredSales {
            var entry = map[sale.itemName, default: (0, 0)]
            entry.qty += sale.quantitySold
            entry.revenue += sale.revenue
            map[sale.itemName] = entry
        }
        return map.map { (name: $0.key, qty: $0.value.qty, revenue: $0.value.revenue) }
            .sorted { $0.revenue > $1.revenue }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodPicker
                    if selectedPeriod == .custom && subscriptionManager.isPro {
                        DatePicker("Start", selection: $customStart, displayedComponents: .date)
                        DatePicker("End", selection: $customEnd, displayedComponents: .date)
                    }
                    summaryCard
                    revenueTrendSection
                    if !filteredSales.isEmpty {
                        topItemsSection
                        marginAlertsSection
                    }
                    movementsSection
                }
                .padding()
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "custom_reports")
                .sheetStyle()
        }
        .onAppear {
            AnalyticsManager.shared.track(.reportViewed(period: selectedPeriod.rawValue))
        }
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    if period == .custom {
                        Button {
                            if subscriptionManager.isPro {
                                selectedPeriod = .custom
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if !subscriptionManager.isPro {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                }
                                Text(period.rawValue)
                            }
                            .font(.caption)
                            .fontWeight(selectedPeriod == period ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedPeriod == period ? Color.stoqlyPrimary.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            selectedPeriod = period
                        } label: {
                            Text(period.rawValue)
                                .font(.caption)
                                .fontWeight(selectedPeriod == period ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPeriod == period ? Color.stoqlyPrimary.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            if filteredSales.isEmpty {
                ContentUnavailableView {
                    Label(allSales.isEmpty ? "No Sales Yet" : "No Sales This Period", systemImage: "chart.bar")
                } description: {
                    Text(allSales.isEmpty
                         ? "Record your first sale to see revenue and profit reports here."
                         : "Record sales from any item to see revenue and profit here.")
                } actions: {
                    if allSales.isEmpty {
                        Button("Record a Sale") {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("stoqly.recordSaleFromReports"),
                                object: nil
                            )
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.stoqlyAccent)
                    }
                }
            } else {
                HStack {
                    summaryColumn("Revenue", currencyManager.formatPrice(totalRevenue), .blue)
                    summaryColumn("COGS", currencyManager.formatPrice(totalCOGS), .secondary)
                    summaryColumn("Profit", currencyManager.formatPrice(totalProfit), totalProfit >= 0 ? .green : .red)
                    if let margin = totalMarginPct {
                        summaryColumn("Margin", String(format: "%.0f%%", margin),
                                      margin >= 30 ? .green : margin >= 10 ? .orange : .red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private func summaryColumn(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var revenueTrendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Revenue Trend")
                .font(.headline)
            if allDays.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(allDays) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Revenue", day.revenue)
                        )
                        .foregroundStyle(Color.stoqlyAccent)
                    }
                }
                .chartXAxis {
                    if useDayNumberAxis {
                        let daySpan = Calendar.current.dateComponents(
                            [.day],
                            from: periodRange.lowerBound,
                            to: periodRange.upperBound
                        ).day ?? 7
                        let strideCount = daySpan > 20 ? 5 : daySpan > 10 ? 3 : 1
                        AxisMarks(values: .stride(by: .day, count: strideCount)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day())
                        }
                    } else {
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private var topItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Items by Revenue")
                .font(.headline)
            ForEach(topItemsByRevenue, id: \.name) { entry in
                HStack {
                    Text(entry.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(entry.qty.smartFormatted) sold · \(currencyManager.formatPrice(entry.revenue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var marginAlertsSection: some View {
        Group {
            let lowMargin = filteredSales.filter { sale in
                guard let pct = sale.grossMarginPct else { return false }
                return pct < 10
            }
            if !lowMargin.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Margin Alerts")
                        .font(.headline)
                    ForEach(Array(Set(lowMargin.map(\.itemName))), id: \.self) { name in
                        let sales = lowMargin.filter { $0.itemName == name }
                        let avgMargin = sales.compactMap(\.grossMarginPct).reduce(0, +) / Double(max(sales.count, 1))
                        Text(avgMargin < 0 ? "\(name): Selling below cost" : "\(name): \(String(format: "%.0f", avgMargin))% margin")
                            .font(.caption)
                            .foregroundColor(avgMargin < 0 ? .red : .orange)
                    }
                }
            }
        }
    }

    private var movementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                movementsExpanded.toggle()
            } label: {
                HStack {
                    Text("Movements")
                        .font(.headline)
                    Spacer()
                    Image(systemName: movementsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if movementsExpanded {
                let inQty = filteredMovements.filter(\.isIN).reduce(0) { $0 + $1.quantity }
                let outQty = filteredMovements.filter { !$0.isIN }.reduce(0) { $0 + $1.quantity }
                let salesOut = filteredMovements.filter { $0.movementType == MovementTypeOut.saleOut.rawValue }.reduce(0) { $0 + $1.quantity }
                let wasteOut = filteredMovements.filter { $0.movementType == MovementTypeOut.waste.rawValue }.reduce(0) { $0 + $1.quantity }

                Text("IN: \(inQty.smartFormatted)  ·  OUT: \(outQty.smartFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Sales: \(salesOut.smartFormatted)  ·  Waste: \(wasteOut.smartFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                NavigationLink {
                    MovementsListView(movements: filteredMovements)
                } label: {
                    Text("View All Movements →")
                        .font(.subheadline)
                        .foregroundColor(.stoqlyPrimary)
                }
            }
        }
    }
}

struct DailyRevenue: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Double
}
