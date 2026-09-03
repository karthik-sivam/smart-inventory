import Foundation
import StoreKit
import SwiftUI
import SwiftData

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
// │  PRO  — the localized StoreKit price. No free trial.            │
// │  Everything in Free, plus:                                      │
// │  • Unlimited storage areas                                      │
// │  • Unlimited items per storage                                  │
// │  • Advanced analytics (full history, trends, custom dates)      │
// │  • Bulk barcode scan (camera stays open)     [iOS-F2]           │
// │  • Multi-user collaboration                  [Phase 2]          │
// │  • AI reorder suggestions                    [Phase 3]          │
// │  • No ads                                                       │
// ├─────────────────────────────────────────────────────────────────┤
// │  REMOVE ADS  one-time purchase                                  │
// │  • Removes all ads only — no other Pro features                 │
// └─────────────────────────────────────────────────────────────────┘
//
// PRICING IS NEVER HARDCODED.
// Every user-facing price comes from StoreKit (`Product.displayPrice`), so the
// storefront's own currency and amount are shown. Do not write a price literal
// into code, copy, or a localized string — it will be wrong in most storefronts
// and drifts the moment App Store Connect changes. Tier comments above describe
// *what* is included, never *what it costs*.
//
// SETUP REQUIRED in App Store Connect:
//   Subscription Group: "Stoqly Pro"
//     Products:
//       com.vishuddhi.stoqly.pro.monthly
//       com.vishuddhi.stoqly.pro.annual
//
//   Non-Consumable IAP:
//       com.vishuddhi.stoqly.removeads     (one-time)
//
//   Stoqly deliberately offers NO free trial. Do not configure an introductory
//   offer in App Store Connect, and do not reintroduce trial copy anywhere.
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
    /// True when Firestore manualProUntil grants Pro independent of StoreKit.
    @Published private(set) var manualProGrantActive = false
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var isLoading = false
    /// Expiration of the active Pro entitlement (subscription renewal date).
    @Published private(set) var proSubscriptionExpirationDate: Date?
    /// Plan label ("monthly" / "annual") of the currently-entitled subscription.
    /// Used to stamp subscription analytics events.
    private(set) var currentPlanLabel: String?

    /// The standalone Remove Ads purchase, held separately from `hasRemovedAds`
    /// (which also folds in Pro) so ad state can be re-resolved after Pro lapses
    /// without rescanning every entitlement.
    private var hasStandaloneRemoveAds = false

    // MARK: - Product IDs

    enum ProductID: String, CaseIterable {
        case proMonthly    = "com.vishuddhi.stoqly.pro.monthly"
        case proAnnual     = "com.vishuddhi.stoqly.pro.annual"
        case removeAds     = "com.vishuddhi.stoqly.removeads"

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

                switch product.id {
                case ProductID.removeAds.rawValue:
                    AnalyticsManager.shared.track(.removeAdsPurchased)
                    logMetaPurchase(for: product)
                case ProductID.proMonthly.rawValue, ProductID.proAnnual.rawValue:
                    let plan = product.id.contains("annual") ? "annual" : "monthly"
                    AnalyticsManager.shared.track(.subscriptionStarted(plan: plan))
                    AnalyticsManager.shared.identify(
                        userId: AuthManager.shared.currentUser?.uid ?? "",
                        email: AuthManager.shared.currentUser?.email,
                        isPro: true,
                        signupMethod: UserDefaults.standard.string(forKey: "signupMethod") ?? "unknown"
                    )
                    logMetaPurchase(for: product)
                default:
                    break
                }

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
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
            let restoredCount = await activeStoreKitEntitlementCount()
            AnalyticsManager.shared.track(
                .restorePurchaseResult(
                    outcome: restoredCount > 0 ? "restored" : "no_purchases",
                    restoredCount: restoredCount,
                    reason: nil
                )
            )
            print("StoreKit ✅ Purchases restored.")
        } catch StoreKitError.userCancelled {
            AnalyticsManager.shared.track(
                .restorePurchaseResult(
                    outcome: "cancelled",
                    restoredCount: 0,
                    reason: "user_cancelled"
                )
            )
        } catch {
            AnalyticsManager.shared.track(
                .restorePurchaseResult(
                    outcome: "storekit_error",
                    restoredCount: 0,
                    reason: error.localizedDescription
                )
            )
            print("StoreKit ❌ Restore failed: \(error.localizedDescription)")
        }
    }

    private func activeStoreKitEntitlementCount() async -> Int {
        var count = 0
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }
            count += 1
        }
        return count
    }

    // MARK: - Status Refresh

    /// Days until the Pro entitlement lapses; `nil` when not Pro or expiry unknown.
    var proDaysRemaining: Int? {
        guard isPro, let expiry = proSubscriptionExpirationDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(0, days)
    }

    func refreshPurchaseStatus() async {
        // Re-fetch manualProUntil so an expired/removed Firestore grant cannot keep
        // isPro / hasRemovedAds sticky across StoreKit-only refreshes.
        manualProGrantActive = await FirestoreManager.shared.fetchManualProGrant()

        var hasPro = false
        var hasNoAds = false
        var proExpiry: Date?
        var planLabel: String?

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }

            // Check subscription hasn't expired
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            switch transaction.productID {
            case ProductID.proMonthly.rawValue, ProductID.proAnnual.rawValue:
                hasPro = true
                if let expiry = transaction.expirationDate {
                    if proExpiry == nil || expiry < proExpiry! {
                        proExpiry = expiry
                    }
                }
                planLabel = Self.planLabel(forProductID: transaction.productID)
            case ProductID.removeAds.rawValue:
                hasNoAds = true
            default:
                break
            }
        }

        isPro = hasPro || manualProGrantActive
        proSubscriptionExpirationDate = proExpiry
        currentPlanLabel = planLabel
        // Pro includes ad removal
        hasStandaloneRemoveAds = hasNoAds
        hasRemovedAds = hasNoAds || hasPro || manualProGrantActive

        // Mirror the resolved entitlement (StoreKit and/or manual grant), not StoreKit alone.
        FirestoreManager.shared.writeProStatus(isPro)
        FCMTopicManager.syncProTopics(isPro: isPro)

        if hasRemovedAds {
            AdManager.shared.disableAds()
        }

        // Runs last: it reads the entitlement state resolved above to decide which
    }

    /// Maps a subscription product ID to the analytics plan label.
    /// The subscription taxonomy uses "monthly" / "yearly" (agreed with data-analyst);
    /// note `subscription_started` predates this and uses "annual" — left untouched.
    private static func planLabel(forProductID id: String) -> String? {
        switch id {
        case ProductID.proMonthly.rawValue: return "monthly"
        case ProductID.proAnnual.rawValue:  return "yearly"
        default:                            return nil
        }
    }

    /// Asks StoreKit whether this customer can still redeem the introductory offer.
    /// Eligibility is per subscription *group*, so either product answers for both.
    /// Applies a manual Pro grant from Firestore (manualProUntil field in Firebase console).
    /// Recomputes StoreKit + grant entitlements so revoked/expired grants clear Pro access.
    func applyManualProGrantIfNeeded() async {
        await refreshPurchaseStatus()
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

    private func logMetaPurchase(for product: Product) {
        let amount = NSDecimalNumber(decimal: product.price).doubleValue
        let currency = Locale.current.currency?.identifier ?? "USD"
        MetaAppEvents.logPurchase(amount: amount, currency: currency)
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.notEntitled
        case .verified(let value): return value
        }
    }

    private func updateEntitlements(for transaction: StoreKit.Transaction) async {
        // Match refreshPurchaseStatus(): never grant from revoked or expired transactions.
        // Transaction.updates can redeliver stale events; writing isPro=true here would
        // overwrite a correct local/Firestore clear from a prior refresh.
        guard transaction.revocationDate == nil else {
            await refreshPurchaseStatus()
            return
        }
        if let expiry = transaction.expirationDate, expiry <= Date() {
            await refreshPurchaseStatus()
            return
        }

        switch transaction.productID {
        case ProductID.proMonthly.rawValue, ProductID.proAnnual.rawValue:
            isPro = true
            hasRemovedAds = true
            if let expiry = transaction.expirationDate {
                proSubscriptionExpirationDate = expiry
            }
            currentPlanLabel = Self.planLabel(forProductID: transaction.productID)
            AdManager.shared.disableAds()
            // Mirror immediately — do not wait for a later refreshPurchaseStatus().
            FirestoreManager.shared.writeProStatus(isPro)
            FCMTopicManager.syncProTopics(isPro: isPro)
            // The optimistic writes above unblock the UI; this resolves the full
            // entitlement picture.
            await refreshPurchaseStatus()
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

    /// Authoritative per-storage count (S44). Uses fetchCount so it does not lag like `storage.items`.
    func itemCount(in storage: Storage, context: ModelContext) -> Int {
        let sid = storage.persistentModelID
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { item in
                item.storage?.persistentModelID == sid
            }
        )
        return (try? context.fetchCount(descriptor)) ?? storage.items.count
    }

    /// Write-time cap check. True when a free user is already at or over the 50-item limit.
    func freeItemCapReached(storage: Storage, context: ModelContext) -> Bool {
        guard !isPro else { return false }
        return itemCount(in: storage, context: context) >= Self.freeItemLimit
    }

    /// Slots left under the free 50-item cap. Pro returns `Int.max`.
    func remainingFreeItemSlots(storage: Storage?, context: ModelContext) -> Int {
        guard !isPro else { return Int.max }
        guard let storage else { return 0 }
        return max(0, Self.freeItemLimit - itemCount(in: storage, context: context))
    }

    /// Advances `runningCount` when a new item may be inserted. Returns false at the free cap.
    func canInsertNewItem(runningCount: inout Int) -> Bool {
        if isPro {
            runningCount += 1
            return true
        }
        guard runningCount < Self.freeItemLimit else { return false }
        runningCount += 1
        return true
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

    /// Free: unlimited single scans. Pro: bulk session (camera stays open, then save all).
    var canUseBarcodeScannerPro: Bool { isPro }

    /// Phase 2 — Pro only.
    var canUseMultiUser: Bool { isPro }

    /// Phase 3 — Pro only.
    var canUseAI: Bool { isPro }

    /// Item photo capture and cloud storage -- Pro only.
    var canUseItemPhotos: Bool { isPro }

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
        return String(
            format: L("Save %.0f%%", "Save %.0f%%"),
            NSDecimalNumber(decimal: savings).doubleValue
        )
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    /// Pre-localized feature name shown in the unlock headline (e.g. unlimited storages).
    var featureContext: String? = nil
    var source: String = "unknown"
    var trigger: String? = nil

    @StateObject private var sub = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PaywallTab = .pro
    @State private var didTrackShown = false

    enum PaywallTab { case pro, removeAds }

    private var paywallHeadline: String {
        if let featureContext, selectedTab == .pro {
            return String(
                format: L("Unlock %@", "Unlock %@"),
                featureContext
            )
        }
        return selectedTab == .pro
            ? L("Upgrade to Stoqly Pro", "Upgrade to Stoqly Pro")
            : L("Remove Ads", "Remove Ads")
    }

    /// Price hint shown in the header — derives from live StoreKit prices
    /// so the user always sees a number even before scrolling to the product cards.
    private var priceHint: String {
        switch selectedTab {
        case .pro:
            if let monthly = sub.proMonthlyProduct {
                return String(
                    format: L("From %@ / month", "From %@ / month"),
                    monthly.displayPrice
                )
            }
            return sub.isLoading
                ? L("Loading pricing…", "Loading pricing…")
                : L("Monthly & annual plans available", "Monthly & annual plans available")
        case .removeAds:
            if let removeAds = sub.removeAdsProduct {
                return String(
                    format: L("%@ · one-time", "%@ · one-time"),
                    removeAds.displayPrice
                )
            }
            return sub.isLoading
                ? L("Loading pricing…", "Loading pricing…")
                : L("One-time purchase", "One-time purchase")
        }
    }

    private var paywallSubtitle: String {
        selectedTab == .pro
            ? L("For businesses that are growing", "For businesses that are growing")
            : L("Support the app · Enjoy ad-free", "Support the app · Enjoy ad-free")
    }

    var body: some View {
        NavigationStack {
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

                        Text(paywallHeadline)
                            .font(.title2).fontWeight(.bold)
                        Text(paywallSubtitle)
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Price hint — always visible so user knows cost
                        // before scrolling to the product cards below.
                        Text(priceHint)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(20)
                            .animation(.easeInOut, value: priceHint)
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
                        VStack(spacing: 10) {
                            Text("Unable to load plans. Check your connection.")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                Task { await sub.loadProducts() }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
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
                                Text(L("paywall.renewalLegal",
                                       "Renews automatically. Cancel any time in App Store settings."))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 2)
                            } else {
                                if let removeAds = sub.removeAdsProduct {
                                    ProductCard(
                                        product: removeAds,
                                        badge: L("One-time purchase", "One-time purchase")
                                    )
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
                            AnalyticsManager.shared.track(.restorePurchaseTapped)
                            Task { await sub.restorePurchases() }
                        }
                        .font(.subheadline).foregroundColor(.blue)

                        // Required by App Store guideline 3.1.2(c)
                        HStack(spacing: 16) {
                            Link("Terms of Use",
                                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            Text("·").foregroundColor(.secondary)
                            Link("Privacy Policy",
                                 destination: URL(string: "https://vishuddhi.in/privacy.html")!)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)

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
                    Button("Close") {
                        AnalyticsManager.shared.track(.paywallDismissed)
                        dismiss()
                    }
                }
            }
            .onChange(of: sub.purchaseState) { _, state in
                if case .success = state { dismiss() }
            }
        }
        .task { await sub.loadProducts() }
        .onAppear {
            guard !didTrackShown else { return }
            didTrackShown = true
            AnalyticsManager.shared.track(.paywallShown(source: source, trigger: trigger))
        }
    }
}

// MARK: - Feature List Views

private struct ProFeatureList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            PaywallSectionHeader(title: "Everything in Free, plus:")

            Group {
                PaywallFeatureRow(icon: "archivebox.fill",          color: .purple, text: "Unlimited storage areas",             note: "Free: 5 max")
                PaywallFeatureRow(icon: "cube.box.fill",            color: .blue,   text: "Unlimited items per storage",         note: "Free: 50 max")
                PaywallFeatureRow(icon: "chart.line.uptrend.xyaxis",color: .green,  text: "Advanced analytics & full history",   note: "Free: 30 days")
                PaywallFeatureRow(icon: "barcode.viewfinder",       color: .orange, text: "Bulk barcode scan — keep the camera open, then save all", note: "Free: single scan + product lookup")
                PaywallFeatureRow(icon: "sparkles",                          color: .stoqlyAccent, text: "Smart Sales Entry — Voice, Photo, Text, CSV & PDF")
                PaywallFeatureRow(icon: "arrow.down.doc.fill",               color: .orange,       text: "AI Purchase Invoice Import")
                PaywallFeatureRow(icon: "mic.fill",                          color: .teal,         text: "AI Voice Inventory Count",   note: "Free: 3/month")
                PaywallFeatureRow(icon: "camera.fill",                       color: .teal,         text: "AI Photo Inventory Scan",    note: "Free: 3/month")
                PaywallFeatureRow(icon: "doc.text.viewfinder",               color: .teal,         text: "AI Sheet Inventory Import",  note: "Free: 3/month")
                PaywallFeatureRow(icon: "square.and.arrow.down.on.square", color: .indigo, text: "Bulk CSV / Excel import")
                PaywallFeatureRow(icon: "person.2.fill",            color: .cyan,   text: "Multi-user collaboration")
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
    let title: LocalizedStringKey
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
    let text: LocalizedStringKey
    var note: LocalizedStringKey? = nil
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

    /// For annual subscriptions we compute the description from live prices so
    /// it always matches the savings badge. The App Store Connect description
    /// field often has a hardcoded percentage that drifts out of sync with the
    /// actual prices — this avoids that mismatch.
    private var displayDescription: String {
        if product.subscription?.subscriptionPeriod.unit == .year,
           let monthly = sub.proMonthlyProduct {
            let annualisedMonthly = monthly.price * 12
            guard annualisedMonthly > 0 else { return product.description }
            let savingPct = (Double(truncating: annualisedMonthly - product.price as NSDecimalNumber)
                            / Double(truncating: annualisedMonthly as NSDecimalNumber)) * 100
            let saving = Int(savingPct.rounded())
            return String(
                format: L("Billed annually · save %lld%% vs monthly", "Billed annually · save %lld%% vs monthly"),
                saving
            )
        }
        return product.description
    }

    private var analyticsPlan: String {
        if product.subscription?.subscriptionPeriod.unit == .month { return "monthly" }
        if product.subscription?.subscriptionPeriod.unit == .year { return "annual" }
        return "remove_ads"
    }


    var body: some View {
        Button {
            AnalyticsManager.shared.track(.paywallCtaTapped(plan: analyticsPlan))
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

                    if !displayDescription.isEmpty {
                        Text(displayDescription)
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
                            Text("/ month", comment: "Subscription period suffix on paywall price")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if product.subscription?.subscriptionPeriod.unit == .year {
                            Text("/ year", comment: "Subscription period suffix on paywall price")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("one-time", comment: "One-time purchase suffix on paywall price")
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
                .sheet(isPresented: $showPaywall) { PaywallView(source: "pro_feature").sheetStyle() }
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
                Text(
                    String(
                        format: L("Pro: %@", "Pro: %@"),
                        featureName
                    )
                )
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
