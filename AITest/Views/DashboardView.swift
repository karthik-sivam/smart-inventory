import SwiftUI
import SwiftData
import UIKit

// Tracks how far the user has scrolled so the header can react
private struct ScrollOffsetKey: PreferenceKey {
    // nonisolated(unsafe): PreferenceKey protocol requires `static var`; this is
    // only ever read as the initial reduction seed — never mutated concurrently.
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DashboardView: View {
    @Binding var selectedTab: Int
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var firestoreManager: FirestoreManager
    @Query private var storages: [Storage]
    @Query private var items: [InventoryItem]
    @Query private var uoms: [UOM]
    @Query(sort: \ActivityEvent.occurredAt, order: .reverse) private var activityEvents: [ActivityEvent]
    @Query(sort: \SaleEvent.occurredAt, order: .reverse) private var allSaleEvents: [SaleEvent]
    @EnvironmentObject private var currencyManager: CurrencyManager
    @State private var showingSettings = false
    @State private var showingProfile = false
    @State private var showingExport = false
    @State private var showingSearch = false
    @State private var showingCategoryExplorer = false
    @State private var showingStorages = false
    @State private var showingAllItems = false
    @State private var showingReorderList = false
    @State private var showingOutOfStockItems = false
    @State private var showingExpiringSoonItems = false
    @State private var showingActivityHistory = false
    @State private var showingPaywall = false
    @State private var showingHealthDetail = false
    @State private var showingValueByCategory = false
    @State private var insightDetailContext: InsightDetailContext? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var dashboardSalesPeriod: DashboardSalesPeriod = .lastThirtyDays
    @State private var showingReports = false
    @State private var localeChangeCurrency: Currency? = nil

    private struct InsightDetailContext: Identifiable {
        let id = UUID()
        let title: String
        let items: [InventoryItem]
    }

    enum DashboardSalesPeriod: String, CaseIterable {
        case today = "Today"
        case thisWeek = "This Week"
        case lastThirtyDays = "Last 30 Days"
        case thisMonth = "This Month"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: Custom header — fades a separator in as content scrolls under it
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stoqly")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Manage your inventory efficiently")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 16) {
                            Button(action: { showingSearch = true }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                            .accessibilityLabel("Search")

                            Button(action: { showingExport = true }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                    .foregroundColor(.stoqlyPrimary)
                            }

                            Button(action: { showingProfile = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                            .accessibilityLabel("Settings and Profile")
                            .accessibilityIdentifier("dashboardGearButton")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    // Separator that fades in as user scrolls
                    Rectangle()
                        .fill(Color(.separator).opacity(min(1, scrollOffset / 16)))
                        .frame(height: 0.5)
                }
                // The background Rectangle extends into the safe area (status bar) so the
                // frosted-glass material fills edge-to-edge. The header VStack itself
                // stays within the safe area — only the background bleeds upward.
                .background(
                    Rectangle()
                        .fill(.bar)
                        .ignoresSafeArea(edges: .top)
                )

                if !subscriptionManager.isPro {
                    ProUpgradeStrip {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("stoqly.showPaywall"),
                            object: nil
                        )
                    }
                }

                if let newCurrency = localeChangeCurrency {
                    HStack(spacing: 12) {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your device region suggests \(newCurrency.name) (\(newCurrency.symbol))")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Switch currency?")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Switch") {
                            currencyManager.selectedCurrency = newCurrency
                            currencyManager.markAsManuallySet()
                            localeChangeCurrency = nil
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(8)
                        Button("Keep") {
                            currencyManager.dismissLocaleChangeBanner(for: newCurrency)
                            localeChangeCurrency = nil
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if case .syncing = firestoreManager.syncState {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(.stoqlyPrimary)
                        Text("Syncing to cloud…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.stoqlyPrimaryTint)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ScrollView {
                    // Invisible anchor at the top — reports scroll position
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: -geo.frame(in: .named("dashScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    VStack(spacing: 16) {
                        // Trial expiry banner
                        if let days = subscriptionManager.trialDaysRemaining, days <= 3 {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.stoqlyWarning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(days == 0 ? "Your trial expires today"
                                                   : "Trial expires in \(days) day\(days == 1 ? "" : "s")")
                                        .font(.subheadline).fontWeight(.semibold)
                                    Text("Upgrade to keep all your Pro features.")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Upgrade") { showingPaywall = true }
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.stoqlyPrimary)
                            }
                            .padding()
                            .background(Color.stoqlyWarningTint)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // KPI grid — 6 gradient cards, 2 columns
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 14) {
                            DashboardCard(
                                title: "Revenue",
                                value: currencyManager.formatPrice(dashboardPeriodRevenue),
                                icon: "cart.fill",
                                gradient: AppTheme.kpiGradients[0],
                                deltaText: dashboardSalesPeriod.rawValue,
                                deltaPositive: dashboardPeriodRevenue > 0 ? true : nil,
                                action: { showingReports = true }
                            )

                            DashboardCard(
                                title: "Gross Profit",
                                value: currencyManager.formatPrice(dashboardPeriodProfit),
                                icon: "chart.line.uptrend.xyaxis",
                                gradient: AppTheme.kpiGradients[1],
                                deltaText: dashboardPeriodMarginText,
                                deltaPositive: dashboardPeriodProfit >= 0 ? true : nil,
                                action: { showingReports = true }
                            )

                            DashboardCard(
                                title: "Low Stock",
                                value: "\(lowStockItems.count)",
                                icon: "exclamationmark.triangle.fill",
                                gradient: AppTheme.kpiGradients[2],
                                action: { showingReorderList = true }
                            )
                            .accessibilityIdentifier("lowStockKpiCard")

                            DashboardCard(
                                title: "Out of Stock",
                                value: "\(outOfStockItems.count)",
                                icon: "xmark.circle.fill",
                                gradient: AppTheme.kpiGradients[3],
                                action: { showingOutOfStockItems = true }
                            )

                            DashboardCard(
                                title: "Expiring Soon",
                                value: "\(expiringSoonItems.count)",
                                icon: "calendar.badge.exclamationmark",
                                gradient: AppTheme.kpiGradients[5],
                                action: { showingExpiringSoonItems = true }
                            )

                            DashboardCard(
                                title: "Total Value",
                                value: currencyManager.formatPrice(totalInventoryValue),
                                icon: "dollarsign.circle.fill",
                                gradient: AppTheme.kpiGradients[4],
                                action: { showingValueByCategory = true }
                            )
                        }
                        .padding(.horizontal)

                        if !items.isEmpty {
                            InventoryHealthCard(items: Array(items))
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                                .onTapGesture { showingHealthDetail = true }
                        }

                        if !priceCreepItems.isEmpty {
                            Button {
                                insightDetailContext = InsightDetailContext(title: "Price Above Unit Cost", items: priceCreepItems)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .foregroundColor(.orange)
                                    Text("\(priceCreepItems.count) item\(priceCreepItems.count == 1 ? "" : "s") purchased above unit cost recently")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.08))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        if !items.isEmpty {
                            SmartInsightsCard(
                                items: Array(items),
                                onShowItems: { title, detailItems in
                                    insightDetailContext = InsightDetailContext(title: title, items: Array(detailItems))
                                }
                            )
                            .padding(.horizontal)
                        }

                        CategoryBarChart(items: Array(items))
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture { showingCategoryExplorer = true }

                        if !items.isEmpty && (items.contains(where: { $0.sellingPrice > 0 }) || !allSaleEvents.isEmpty) {
                            salesPerformanceSection
                                .padding(.horizontal)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Activity")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                if activityEvents.count > 10 {
                                    Button("See All") { showingActivityHistory = true }
                                        .font(.caption)
                                        .foregroundColor(.stoqlyPrimary)
                                }
                            }
                            .padding(.horizontal)

                            if activityEvents.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 36))
                                        .foregroundColor(.gray)
                                    Text("No activity yet")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("Activity appears here as you add items\nand record counts.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(activityEvents.prefix(10), id: \.id) { event in
                                        ActivityEventRow(event: event)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        Spacer(minLength: 20)
                    }
                }
                .coordinateSpace(name: "dashScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    scrollOffset = max(0, value)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .animation(.easeInOut(duration: 0.3), value: firestoreManager.syncState)
        }
        .onAppear {
            initializeStandardUOMs()
            AnalyticsManager.shared.track(.dashboardViewed)
            if let suggested = currencyManager.checkLocaleChange() {
                withAnimation { localeChangeCurrency = suggested }
            }
            Task {
                try? await Task.sleep(for: .seconds(8))
                if localeChangeCurrency != nil {
                    withAnimation { localeChangeCurrency = nil }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if let suggested = currencyManager.checkLocaleChange() {
                withAnimation { localeChangeCurrency = suggested }
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(currencyManager)
                .environmentObject(firestoreManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(currencyManager)
                .environmentObject(firestoreManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView()
                .sheetStyle()
        }
        .sheet(isPresented: $showingCategoryExplorer) {
            CategoryExplorerView()
                .sheetStyle()
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
                .sheetStyle()
        }
        .sheet(isPresented: $showingStorages) {
            StorageListView()
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingAllItems) {
            ItemListView()
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingReorderList) {
            ReorderListView(items: reorderItems)
                .sheetStyle()
        }
        .sheet(isPresented: $showingOutOfStockItems) {
            FilteredItemListView(
                title: "Out of Stock Items",
                items: outOfStockItems,
                filterType: .outOfStock
            )
            .environmentObject(currencyManager)
            .sheetStyle()
        }
        .sheet(isPresented: $showingExpiringSoonItems) {
            ExpiryTimelineView(items: expiringSoonItems)
                .sheetStyle()
        }
        .sheet(isPresented: $showingActivityHistory) {
            ActivityHistoryView(events: activityEvents)
                .sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "pro_feature")
                .sheetStyle()
        }
        .sheet(isPresented: $showingHealthDetail) {
            HealthDetailView(items: Array(items), selectedTab: $selectedTab)
                .sheetStyle()
        }
        .sheet(isPresented: $showingValueByCategory) {
            ValueByCategoryView(items: Array(items))
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(item: $insightDetailContext) { ctx in
            InsightDetailView(title: ctx.title, items: ctx.items)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingReports) {
            ReportsView(selectedPeriod: dashboardPeriodAsReportPeriod)
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
    }

    private var dashboardPeriodRange: ClosedRange<Date> {
        let now = Date()
        let cal = Calendar.current
        switch dashboardSalesPeriod {
        case .today:
            return cal.startOfDay(for: now)...now
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return start...now
        case .lastThirtyDays:
            let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return start...now
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return start...now
        }
    }

    private var filteredDashboardSales: [SaleEvent] {
        allSaleEvents.filter { dashboardPeriodRange.contains($0.occurredAt) }
    }

    private var dashboardPeriodRevenue: Double {
        filteredDashboardSales.reduce(0) { $0 + $1.revenue }
    }

    private var dashboardPeriodProfit: Double {
        filteredDashboardSales.reduce(0) { $0 + $1.grossProfit }
    }

    private var dashboardPeriodMargin: Double? {
        guard dashboardPeriodRevenue > 0 else { return nil }
        return dashboardPeriodProfit / dashboardPeriodRevenue * 100
    }

    private var dashboardPeriodMarginText: String? {
        guard let margin = dashboardPeriodMargin else { return nil }
        return String(format: "%.0f%% margin", margin)
    }

    private var dashboardPeriodAsReportPeriod: ReportsView.ReportPeriod {
        switch dashboardSalesPeriod {
        case .today: return .today
        case .thisWeek: return .thisWeek
        case .lastThirtyDays: return .last30Days
        case .thisMonth: return .thisMonth
        }
    }

    private var salesPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sales Performance")
                .font(.headline)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DashboardSalesPeriod.allCases, id: \.self) { period in
                        Button {
                            dashboardSalesPeriod = period
                        } label: {
                            Text(period.rawValue)
                                .font(.caption)
                                .fontWeight(dashboardSalesPeriod == period ? .semibold : .regular)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    dashboardSalesPeriod == period
                                        ? Color.stoqlyPrimary.opacity(0.15)
                                        : Color(.tertiarySystemGroupedBackground)
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            if allSaleEvents.isEmpty {
                VStack(spacing: 8) {
                    Text("No sales recorded yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Start recording sales to see your profit insights here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Record Your First Sale →") {
                        selectedTab = 1
                    }
                    .font(.caption)
                    .foregroundColor(.stoqlyPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 4) {
                    GridRow {
                        Text("Revenue")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Profit")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if dashboardPeriodMargin != nil {
                            Text("Margin")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GridRow {
                        Text(currencyManager.formatPrice(dashboardPeriodRevenue))
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(currencyManager.formatPrice(dashboardPeriodProfit))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(dashboardPeriodProfit >= 0 ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let margin = dashboardPeriodMargin {
                            Text(String(format: "%.0f%%", margin))
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(margin >= 30 ? .green : margin >= 10 ? .orange : .red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Divider()

                Button {
                    showingReports = true
                } label: {
                    HStack {
                        Text("View Full Report →")
                            .font(.subheadline)
                            .foregroundColor(.stoqlyPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var lowStockItems: [InventoryItem] {
        items.filter { $0.isLowStock }
    }

    /// Rolling 7-day window used for the dashboard "+N this week" delta badges.
    private var sevenDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    private var itemsAddedThisWeek: Int {
        activityEvents.filter {
            $0.eventType == "ItemAdded" && $0.occurredAt >= sevenDaysAgo
        }.count
    }

    private var storagesAddedThisWeek: Int {
        activityEvents.filter {
            $0.eventType == "StorageCreated" && $0.occurredAt >= sevenDaysAgo
        }.count
    }

    private var outOfStockItems: [InventoryItem] {
        items.filter(\.isOutOfStock)
    }

    private var expiringSoonItems: [InventoryItem] {
        items.filter { $0.isExpiringSoon || $0.isExpired }
    }

    private var reorderItems: [InventoryItem] {
        let combined = lowStockItems + outOfStockItems
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0.id).inserted }
    }

    private var priceCreepItems: [InventoryItem] {
        items.filter {
            $0.lastPurchasePrice > 0 &&
            $0.unitCost > 0 &&
            $0.lastPurchasePrice > $0.unitCost * 1.10
        }
    }

    private var totalInventoryValue: Double {
        items.reduce(0) { $0 + $1.totalValue }
    }

    private func initializeStandardUOMs() {
        if uoms.isEmpty {
            for standardUOM in UOM.standardUOMs {
                modelContext.insert(standardUOM)
            }
            modelContext.safeSave(context: "initializeStandardUOMs")
        }
    }
}

// MARK: - Dashboard Card
//
// Full-bleed gradient card. Each card gets one of the 6 AppTheme.kpiGradients
// so every KPI has its own distinct colour — far more scannable than white tiles.

struct DashboardCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: (Color, Color)
    let deltaText: String?
    let deltaPositive: Bool?
    let action: (() -> Void)?

    init(
        title: String,
        value: String,
        icon: String,
        gradient: (Color, Color),
        deltaText: String? = nil,
        deltaPositive: Bool? = nil,
        action: (() -> Void)?
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.gradient = gradient
        self.deltaText = deltaText
        self.deltaPositive = deltaPositive
        self.action = action
    }

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon row
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Spacer(minLength: 14)

                // Value
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                // Title
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.82))
                    .padding(.top, 2)

                // Delta badge (optional)
                if let delta = deltaText, deltaPositive != nil {
                    Text(delta)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.25))
                        .cornerRadius(5)
                        .padding(.top, 6)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [gradient.0, gradient.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            // Subtle inner shadow to give depth to the gradient
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(color: gradient.0.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Inventory Health Card

/// Compact 0–100 score summarising stock health: weighted by out-of-stock items,
/// low-stock items, and the share of items counted in the last 30 days. Shown
/// above the category charts on the Dashboard when at least one item exists.
private struct InventoryHealthCard: View {
    let items: [InventoryItem]

    private var score: Int {
        guard !items.isEmpty else { return 100 }
        var pts = 0

        // +35 if zero out-of-stock items
        let outOfStock = items.filter(\.isOutOfStock).count
        if outOfStock == 0 { pts += 35 }

        // +25 if zero low-stock items
        let lowStock = items.filter(\.isLowStock).count
        if lowStock == 0 { pts += 25 }

        // +40 proportional to % of items counted in last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentlyCounted = items.filter { item in
            item.countHistory.map(\.countDate).max().map { $0 >= thirtyDaysAgo } ?? false
        }.count
        let countFraction = Double(recentlyCounted) / Double(items.count)
        pts += Int(countFraction * 40)

        return min(pts, 100)
    }

    private var label: String {
        score >= 80 ? "Good" : score >= 50 ? "Fair" : "Needs Attention"
    }

    private var labelColor: Color {
        score >= 80 ? .stoqlySuccess : score >= 50 ? .stoqlyWarning : .stoqlyDanger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inventory Health")
                    .font(.headline).fontWeight(.semibold)
                Spacer()
                Text("\(score)")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(labelColor)
                Text("/ 100")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(labelColor)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 8)
                        .animation(.easeInOut(duration: 0.6), value: score)
                }
            }
            .frame(height: 8)

            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(labelColor)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Health Detail

private struct HealthDetailView: View {
    let items: [InventoryItem]
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: InventoryItem? = nil

    private var outOfStockItems: [InventoryItem] {
        items.filter(\.isOutOfStock)
    }

    private var lowStockItems: [InventoryItem] {
        items.filter { $0.isLowStock && !$0.isOutOfStock }
    }

    private var uncountedItems: [InventoryItem] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return items.filter { item in
            guard let lastCount = item.countHistory.map(\.countDate).max() else { return true }
            return lastCount < thirtyDaysAgo
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !outOfStockItems.isEmpty {
                    Section {
                        ForEach(outOfStockItems, id: \.id) { item in
                            HealthDetailRow(item: item, badge: "Out of Stock", badgeColor: .red)
                                .onTapGesture { selectedItem = item }
                        }
                    } header: {
                        Label("Out of Stock — \(outOfStockItems.count) item\(outOfStockItems.count == 1 ? "" : "s") (−35 pts)", systemImage: "xmark.circle.fill")
                            .foregroundColor(.stoqlyDanger)
                    }
                }

                if !lowStockItems.isEmpty {
                    Section {
                        ForEach(lowStockItems, id: \.id) { item in
                            HealthDetailRow(item: item, badge: "Low Stock", badgeColor: .stoqlyWarning)
                                .onTapGesture { selectedItem = item }
                        }
                    } header: {
                        Label("Low Stock — \(lowStockItems.count) item\(lowStockItems.count == 1 ? "" : "s") (−25 pts)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.stoqlyWarning)
                    }
                }

                if !uncountedItems.isEmpty {
                    Section {
                        ForEach(uncountedItems, id: \.id) { item in
                            HealthDetailRow(item: item, badge: "Not counted", badgeColor: .secondary)
                                .onTapGesture { selectedItem = item }
                        }
                    } header: {
                        Label("Not counted in 30 days — \(uncountedItems.count) item\(uncountedItems.count == 1 ? "" : "s") (audit score impact)", systemImage: "calendar.badge.exclamationmark")
                            .foregroundColor(.secondary)
                    }

                    Section {
                        Button {
                            dismiss()
                            selectedTab = 4
                        } label: {
                            Label("Go to Audit Tab", systemImage: "checkmark.shield")
                                .foregroundColor(.stoqlyPrimary)
                        }
                    }
                }

                if outOfStockItems.isEmpty && lowStockItems.isEmpty && uncountedItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.stoqlySuccess)
                        Text("All Good!")
                            .font(.title3).fontWeight(.semibold)
                        Text("No issues affecting your inventory health.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .navigationTitle("Inventory Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    ItemDetailView(item: item)
                }
                .sheetStyle()
            }
        }
    }
}

private struct HealthDetailRow: View {
    let item: InventoryItem
    let badge: String
    let badgeColor: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline).fontWeight(.medium)
                Text(item.storage?.name ?? "No Storage")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(badgeColor.opacity(0.12))
                .foregroundColor(badgeColor)
                .cornerRadius(4)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Smart Insights

private struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let relatedItems: [InventoryItem]
}

private struct SmartInsightsCard: View {
    let items: [InventoryItem]
    let onShowItems: (String, [InventoryItem]) -> Void

    private var insights: [Insight] {
        var result: [Insight] = []

        // --- Data-health nudges (shown first so users fix data quality before acting on insights) ---

        let noCost = items.filter { $0.unitCost == 0 && $0.lastPurchasePrice == 0 }
        if !noCost.isEmpty {
            result.append(Insight(
                icon: "cart.badge.questionmark",
                iconColor: .purple,
                title: "Missing cost prices",
                subtitle: "\(noCost.count) item\(noCost.count == 1 ? "" : "s") have no cost price — profit margin tracking is incomplete",
                relatedItems: noCost
            ))
        }

        let noSelling = items.filter { $0.sellingPrice == 0 }
        if !noSelling.isEmpty {
            result.append(Insight(
                icon: "tag.slash",
                iconColor: .teal,
                title: "Missing selling prices",
                subtitle: "\(noSelling.count) item\(noSelling.count == 1 ? "" : "s") have no selling price — revenue tracking won't be accurate",
                relatedItems: noSelling
            ))
        }

        let noMin = items.filter { $0.minQuantity == 0 && $0.reorderPercentage == 0 }
        if !noMin.isEmpty {
            result.append(Insight(
                icon: "bell.slash",
                iconColor: .orange,
                title: "Low-stock alerts disabled",
                subtitle: "\(noMin.count) item\(noMin.count == 1 ? "" : "s") have no minimum quantity — you won't get restock alerts",
                relatedItems: noMin
            ))
        }

        // --- Operational insights ---

        let soonOOS = items.compactMap { item -> (InventoryItem, Int)? in
            guard item.currentQuantity > 0 else { return nil }
            let counts = item.countHistory.sorted { $0.countDate < $1.countDate }
            guard counts.count >= 2 else { return nil }
            let days = Calendar.current.dateComponents([.day],
                from: counts.first!.countDate,
                to: counts.last!.countDate).day ?? 0
            guard days > 0 else { return nil }
            let qtyChange = counts.first!.countedQuantity - counts.last!.countedQuantity
            guard qtyChange > 0 else { return nil }
            let dailyRate = qtyChange / Double(days)
            let daysLeft = Int(item.currentQuantity / dailyRate)
            return daysLeft <= 7 ? (item, daysLeft) : nil
        }
        if !soonOOS.isEmpty {
            let names = soonOOS.prefix(2).map { "\($0.0.name) (~\($0.1)d)" }.joined(separator: ", ")
            result.append(Insight(
                icon: "clock.badge.exclamationmark",
                iconColor: .red,
                title: "Running low soon",
                subtitle: "\(soonOOS.count) item\(soonOOS.count == 1 ? "" : "s") may run out within 7 days: \(names)",
                relatedItems: soonOOS.map { $0.0 }
            ))
        }

        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let deadStock = items.filter { item in
            guard item.currentQuantity > 0 else { return false }
            guard item.createdAt < thirtyDaysAgo else { return false }
            if let lastCount = item.countHistory.map(\.countDate).max() {
                return lastCount < sixtyDaysAgo
            }
            return true
        }
        if !deadStock.isEmpty {
            result.append(Insight(
                icon: "moon.zzz",
                iconColor: .indigo,
                title: "Possible dead stock",
                subtitle: "\(deadStock.count) item\(deadStock.count == 1 ? "" : "s") with stock haven't been touched in 60+ days",
                relatedItems: Array(deadStock)
            ))
        }

        let atRisk = items.filter { $0.isLowStock || $0.isOutOfStock }
        if !atRisk.isEmpty {
            let atRiskValue = atRisk.reduce(0.0) { $0 + $1.totalValue }
            if atRiskValue > 0 {
                result.append(Insight(
                    icon: "exclamationmark.triangle",
                    iconColor: .orange,
                    title: "Inventory value at risk",
                    subtitle: "\(atRisk.count) low/OOS item\(atRisk.count == 1 ? "" : "s") represent stock that needs restocking",
                    relatedItems: atRisk
                ))
            }
        }

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let neverCounted = items.filter { $0.countHistory.isEmpty && $0.createdAt < sevenDaysAgo }
        if !neverCounted.isEmpty {
            result.append(Insight(
                icon: "questionmark.circle",
                iconColor: .secondary,
                title: "Never audited",
                subtitle: "\(neverCounted.count) item\(neverCounted.count == 1 ? "" : "s") have never been counted — quantities unverified",
                relatedItems: neverCounted
            ))
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Smart Insights", systemImage: "sparkles")
                    .font(.headline).fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if insights.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.stoqlySuccess)
                    Text("Everything looks healthy — no issues detected.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else {
                ForEach(insights) { insight in
                    Divider().padding(.leading, 16)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.icon)
                            .foregroundColor(insight.iconColor)
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.title)
                                .font(.subheadline).fontWeight(.semibold)
                            Text(insight.subtitle)
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if !insight.relatedItems.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !insight.relatedItems.isEmpty else { return }
                        onShowItems(insight.title, Array(insight.relatedItems))
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }
}

private struct InsightDetailView: View {
    let title: String
    let items: [InventoryItem]
    @EnvironmentObject private var currencyManager: CurrencyManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: InventoryItem? = nil

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "tray")
                } else {
                    List {
                        ForEach(items, id: \.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.subheadline).fontWeight(.medium)
                                    Text(item.storage?.name ?? "No Storage")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "")")
                                        .font(.subheadline).fontWeight(.semibold)
                                    if item.totalValue > 0 {
                                        Text(currencyManager.formatPrice(item.totalValue))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedItem = item }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack { ItemDetailView(item: item) }
                    .sheetStyle()
            }
        }
    }
}

#Preview {
    DashboardView(selectedTab: .constant(0))
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self, ActivityEvent.self, SaleEvent.self, InventoryMovement.self], inMemory: true)
        .environmentObject(CurrencyManager())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(FirestoreManager.shared)
}

