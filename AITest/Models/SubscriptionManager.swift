import Foundation
import StoreKit
import SwiftUI

// MARK: - SubscriptionManager
//
// Tier structure:
//
// ┌─────────────────────────────────────────────────────────────────┐
// │  FREE (ad-supported)                                            │
// │  • Cloud sync (Firestore)                                       │
// │  • Up to 5 storage areas                                        │
// │  • Up to 50 items per storage                                   │
// │  • Analytics: last 30 days                                      │
// │  • PDF export                                                   │
// │  • Push notifications (low stock alerts)                        │
// ├─────────────────────────────────────────────────────────────────┤
// │  PRO  $2.99/month · $22.99/year (7-day free trial)              │
// │  Everything in Free, plus:                                      │
// │  • Unlimited storage areas                                      │
// │  • Unlimited items per storage                                  │
// │  • Advanced analytics (full history, trends, custom dates)      │
// │  • Barcode scanner pro (bulk, history)       [Phase 1]          │
// │  • Multi-user collaboration                  [Phase 2]          │
// │  • AI reorder suggestions                    [Phase 3]          │
// │  • No ads                                                       │
// ├─────────────────────────────────────────────────────────────────┤
// │  REMOVE ADS  $3.99 one-time purchase                            │
// │  • Removes all ads only — no other Pro features                 │
// └─────────────────────────────────────────────────────────────────┘
//
// SETUP REQUIRED in App Store Connect:
//   Subscription Group: "Smart Inventory Pro"
//     Products:
//       com.vishuddhi.smartinventory.pro.monthly   $2.99/mo
//       com.vishuddhi.smartinventory.pro.annual    $22.99/yr
//
//   Non-Consumable IAP:
//       com.vishuddhi.smartinventory.removeads     $3.99 (one-time)
//
//   In Xcode: Target → Signing & Capabilities → + → In-App Purchase
//   For local testing: assign SmartInventory.storekit to your Run scheme.

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Free Tier Limits

    /// Maximum storage areas allowed on the free plan.
    static let freeStorageLimit = 5

    /// Maximum items per storage on the free plan.
    static let freeItemLimit = 50

    /// Maximum days of analytics history on the free plan.
    static let freeAnalyticsDays = 30

    // MARK: - Published State

    @Published var isPro = false
    @Published var hasRemovedAds = false
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var isLoading = false

    // MARK: - Product IDs

    enum ProductID: String, CaseIterable {
        case proMonthly    = "com.vishuddhi.smartinventory.pro.monthly"
        case proAnnual     = "com.vishuddhi.smartinventory.pro.annual"
        case removeAds     = "com.vishuddhi.smartinventory.removeads"

        var displayName: String {
            switch self {
            case .proMonthly:  return "Pro Monthly"
            case .proAnnual:   return "Pro Annual"
            case .removeAds:   return "Remove Ads"
            }
        }
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success(String)
        case failed(String)
        case cancelled

        static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.purchasing, .purchasing), (.cancelled, .cancelled):
                return true
            case (.success(let a), .success(let b)): return a == b
            case (.failed(let a), .failed(let b)):   return a == b
            default: return false
            }
        }
    }

    // MARK: - Singleton

    static let shared = SubscriptionManager()

    private var transactionListenerTask: Task<Void, Error>?

    private init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            let ids = ProductID.allCases.map { $0.rawValue }
            let fetched = try await Product.products(for: Set(ids))

            // Sort: Pro Monthly → Pro Annual → Remove Ads
            let order = [ProductID.proMonthly.rawValue,
                         ProductID.proAnnual.rawValue,
                         ProductID.removeAds.rawValue]
            products = fetched.sorted {
                (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99)
            }
            await refreshPurchaseStatus()
            print("StoreKit ✅ Loaded \(products.count) products.")
        } catch {
            print("StoreKit ❌ Failed to load products: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlements(for: transaction)
                await transaction.finish()
                purchaseState = .success(product.displayName)
                print("StoreKit ✅ Purchased: \(product.id)")

            case .pending:
                purchaseState = .idle
                print("StoreKit ⏳ Purchase pending parental approval.")

            case .userCancelled:
                purchaseState = .cancelled

            @unknown default:
                purchaseState = .idle
            }
        } catch StoreKitError.userCancelled {
            purchaseState = .cancelled
        } catch {
            purchaseState = .failed(error.localizedDescription)
            print("StoreKit ❌ Purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
            print("StoreKit ✅ Purchases restored.")
        } catch {
            print("StoreKit ❌ Restore failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Status Refresh

    func refreshPurchaseStatus() async {
        var hasPro = false
        var hasNoAds = false

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }

            // Check subscription hasn't expired
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            switch transaction.productID {
            case ProductID.proMonthly.rawValue, ProductID.proAnnual.rawValue:
                hasPro = true
            case ProductID.removeAds.rawValue:
                hasNoAds = true
            default:
                break
            }
        }

        isPro = hasPro
        // Pro includes ad removal
        hasRemovedAds = hasNoAds || hasPro

        if hasRemovedAds {
            AdManager.shared.disableAds()
        }

        print("StoreKit: isPro=\(isPro), hasRemovedAds=\(hasRemovedAds)")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) { [weak self] in
            for await result in StoreKit.Transaction.updates {
                do {
                    guard let self else { return }
                    let transaction = try self.checkVerified(result)
                    await self.updateEntitlements(for: transaction)
                    await transaction.finish()
                } catch {
                    print("StoreKit: Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.notEntitled
        case .verified(let value): return value
        }
    }

    private func updateEntitlements(for transaction: StoreKit.Transaction) async {
        switch transaction.productID {
        case ProductID.proMonthly.rawValue, ProductID.proAnnual.rawValue:
            isPro = true
            hasRemovedAds = true
            AdManager.shared.disableAds()
        case ProductID.removeAds.rawValue:
            hasRemovedAds = true
            AdManager.shared.disableAds()
        default:
            break
        }
    }

    // MARK: - Feature Gates
    //
    // Use these throughout the app to check entitlements.
    // Each function documents exactly what free users can do.

    /// Free: up to 5 storages. Pro: unlimited.
    func canCreateStorage(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeStorageLimit
    }

    /// Free: up to 50 items per storage. Pro: unlimited.
    func canAddItem(currentItemCount: Int) -> Bool {
        isPro || currentItemCount < Self.freeItemLimit
    }

    /// Free: last 30 days. Pro: full history + trend charts.
    var analyticsDateLimit: Date? {
        isPro ? nil : Calendar.current.date(byAdding: .day, value: -Self.freeAnalyticsDays, to: Date())
    }

    /// Free: basic dashboard. Pro: trends, custom date ranges, category breakdown.
    var canUseAdvancedAnalytics: Bool { isPro }

    /// Free: included. Pro: included.
    var canUseCloudSync: Bool { true }

    /// Free: included. Pro: included.
    var canExportPDF: Bool { true }

    /// Free: included. Pro: included.
    var canUsePushNotifications: Bool { true }

    /// Free: basic scanner. Pro: bulk scan, history, custom formats.
    var canUseBarcodeScannerPro: Bool { isPro }

    /// Phase 2 — Pro only.
    var canUseMultiUser: Bool { isPro }

    /// Phase 3 — Pro only.
    var canUseAI: Bool { isPro }

    /// Ads shown unless Pro or Remove Ads active.
    var shouldShowAds: Bool { !isPro && !hasRemovedAds }

    // MARK: - Product Accessors

    var proMonthlyProduct: Product? { products.first { $0.id == ProductID.proMonthly.rawValue } }
    var proAnnualProduct: Product?  { products.first { $0.id == ProductID.proAnnual.rawValue  } }
    var removeAdsProduct: Product?  { products.first { $0.id == ProductID.removeAds.rawValue  } }

    func formattedPrice(for id: ProductID) -> String {
        products.first { $0.id == id.rawValue }?.displayPrice ?? "—"
    }

    var annualSavingsText: String {
        guard let monthly = proMonthlyProduct,
              let annual  = proAnnualProduct,
              monthly.price > 0 else { return "" }
        let savings = ((monthly.price * 12 - annual.price) / (monthly.price * 12)) * 100
        return String(format: "Save %.0f%%", NSDecimalNumber(decimal: savings).doubleValue)
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @StateObject private var sub = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PaywallTab = .pro

    enum PaywallTab { case pro, removeAds }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: selectedTab == .pro ? "star.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: selectedTab == .pro ? [.blue, .purple] : [.orange, .red],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)

                        Text(selectedTab == .pro ? "Smart Inventory Pro" : "Remove Ads")
                            .font(.title2).fontWeight(.bold)
                        Text(selectedTab == .pro
                             ? "For businesses that are growing"
                             : "Support the app · Enjoy ad-free")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Tab toggle
                    Picker("Plan", selection: $selectedTab) {
                        Text("Go Pro").tag(PaywallTab.pro)
                        Text("Remove Ads").tag(PaywallTab.removeAds)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Feature list
                    if selectedTab == .pro {
                        ProFeatureList()
                    } else {
                        RemoveAdsFeatureList()
                    }

                    // Product cards
                    if sub.isLoading {
                        ProgressView("Loading plans…").padding()
                    } else if sub.products.isEmpty {
                        Text("Unable to load plans. Check your connection.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding()
                    } else {
                        VStack(spacing: 12) {
                            if selectedTab == .pro {
                                // Annual (best value, shown first)
                                if let annual = sub.proAnnualProduct {
                                    ProductCard(product: annual, badge: sub.annualSavingsText)
                                }
                                if let monthly = sub.proMonthlyProduct {
                                    ProductCard(product: monthly, badge: nil)
                                }
                            } else {
                                if let removeAds = sub.removeAdsProduct {
                                    ProductCard(product: removeAds, badge: "One-time purchase")
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Free tier reminder
                    if selectedTab == .pro {
                        FreeIncludedBanner()
                    }

                    // Legal
                    VStack(spacing: 12) {
                        Button("Restore Purchases") {
                            Task { await sub.restorePurchases() }
                        }
                        .font(.subheadline).foregroundColor(.blue)

                        if selectedTab == .pro {
                            Text("Pro subscriptions auto-renew. Cancel anytime in Settings → Apple ID → Subscriptions.")
                                .font(.caption2).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        } else {
                            Text("Remove Ads is a one-time purchase. Payment is charged to your Apple ID account.")
                                .font(.caption2).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: sub.purchaseState) { state in
                if case .success = state { dismiss() }
            }
        }
        .task { await sub.loadProducts() }
    }
}

// MARK: - Feature List Views

private struct ProFeatureList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            PaywallSectionHeader(title: "Everything in Free, plus:")

            Group {
                PaywallFeatureRow(icon: "archivebox.fill",          color: .purple, text: "Unlimited storage areas",           note: "Free: 5 max")
                PaywallFeatureRow(icon: "cube.box.fill",            color: .blue,   text: "Unlimited items per storage",       note: "Free: 50 max")
                PaywallFeatureRow(icon: "chart.line.uptrend.xyaxis",color: .green,  text: "Advanced analytics & full history", note: "Free: 30 days")
                PaywallFeatureRow(icon: "barcode.viewfinder",       color: .orange, text: "Barcode scanner pro")
                PaywallFeatureRow(icon: "person.2.fill",            color: .teal,   text: "Multi-user collaboration",          note: "Phase 2")
                PaywallFeatureRow(icon: "sparkles",                 color: .indigo, text: "AI reorder suggestions",           note: "Phase 3")
                PaywallFeatureRow(icon: "xmark.circle.fill",        color: .gray,   text: "No ads")
            }

            PaywallSectionHeader(title: "Already included free:")

            Group {
                PaywallFeatureRow(icon: "icloud.fill",     color: .blue,   text: "Cloud sync across devices", isFree: true)
                PaywallFeatureRow(icon: "doc.fill",        color: .red,    text: "PDF export",                isFree: true)
                PaywallFeatureRow(icon: "bell.badge.fill", color: .yellow, text: "Low stock notifications",   isFree: true)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

private struct RemoveAdsFeatureList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaywallSectionHeader(title: "What you get:")
            PaywallFeatureRow(icon: "xmark.circle.fill",  color: .orange, text: "No banner ads")
            PaywallFeatureRow(icon: "xmark.circle.fill",  color: .orange, text: "No interstitial ads")
            PaywallFeatureRow(icon: "heart.fill",         color: .pink,   text: "Support indie development")

            PaywallSectionHeader(title: "Still included free:")
            PaywallFeatureRow(icon: "icloud.fill",        color: .blue,   text: "Cloud sync",          isFree: true)
            PaywallFeatureRow(icon: "doc.fill",           color: .red,    text: "PDF export",          isFree: true)
            PaywallFeatureRow(icon: "bell.badge.fill",    color: .yellow, text: "Push notifications",  isFree: true)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

private struct FreeIncludedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("Cloud sync, PDF export & push notifications are **always free** — no upgrade needed.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.green.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

private struct PaywallSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let color: Color
    let text: String
    var note: String? = nil
    var isFree: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isFree ? .secondary : color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(isFree ? .secondary : .primary)

            Spacer()

            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }

            if isFree {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 5)
    }
}

struct ProductCard: View {
    @StateObject private var sub = SubscriptionManager.shared
    let product: Product
    let badge: String?

    var body: some View {
        Button {
            Task { await sub.purchase(product) }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if let badge, !badge.isEmpty {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                    }

                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if case .purchasing = sub.purchaseState {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text(product.displayPrice)
                            .font(.title3).fontWeight(.bold)

                        if product.subscription?.subscriptionPeriod.unit == .month {
                            Text("/ month")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if product.subscription?.subscriptionPeriod.unit == .year {
                            Text("/ year")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("one-time")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(sub.purchaseState == .purchasing)
    }
}

// MARK: - Pro Gate Modifier

struct ProGate: ViewModifier {
    @StateObject private var sub = SubscriptionManager.shared
    @State private var showPaywall = false
    let feature: String

    func body(content: Content) -> some View {
        if sub.isPro {
            content
        } else {
            content
                .disabled(true)
                .overlay(
                    ProLockOverlay(featureName: feature) { showPaywall = true }
                )
                .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

struct ProLockOverlay: View {
    let featureName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("Pro: \(featureName)")
            }
            .font(.caption).fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(10)
        }
    }
}

extension View {
    func proGated(feature: String) -> some View {
        modifier(ProGate(feature: feature))
    }
}
