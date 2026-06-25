import Foundation
import AmplitudeSwift

// MARK: - AnalyticsManager
//
// Central analytics layer for Stoqly. Wraps Amplitude so the rest of the app
// never imports AmplitudeSwift directly — making it trivial to swap SDKs later.
//
// Setup:
//   1. Add package in Xcode → File → Add Package Dependencies:
//      URL: https://github.com/amplitude/Amplitude-Swift
//      Version: Up to Next Major from 1.0.0
//      Product: AmplitudeSwift
//   2. Add your key to Secrets.plist:
//      Key = AMPLITUDE_API_KEY   Type = String   Value = <your Amplitude project API key>
//   3. Initialisation happens automatically in AppDelegate — nothing else needed.
//
// Usage anywhere in the app:
//   AnalyticsManager.shared.track(.itemAdded(category: item.category, hasBarcode: true))
//   AnalyticsManager.shared.identify(userId: uid, isPro: true, storageCount: 3, itemCount: 47)

final class AnalyticsManager: @unchecked Sendable {

    // MARK: - Singleton
    static let shared = AnalyticsManager()
    private init() {}

    private var amplitude: Amplitude?
    private var isConfigured = false

    // MARK: - Configure (call once in AppDelegate, after FirebaseApp.configure())

    func configure(apiKey: String) {
        guard !isConfigured, !apiKey.isEmpty else { return }
        let config = Configuration(
            apiKey: apiKey,
            trackingOptions: TrackingOptions(),   // respects ATT
            autocapture: [.sessions]              // auto-track session start/end
        )
        amplitude = Amplitude(configuration: config)
        isConfigured = true
        #if DEBUG
        print("📊 Amplitude configured.")
        #endif
    }

    // MARK: - Identify user

    /// Call after sign-in or whenever user properties change.
    func identify(
        userId: String,
        isPro: Bool,
        storageCount: Int = 0,
        itemCount: Int = 0,
        signupMethod: String = "unknown"
    ) {
        amplitude?.setUserId(userId: userId)
        let identify = Identify()
        identify.set(property: "is_pro",        value: isPro)
        identify.set(property: "storage_count", value: storageCount)
        identify.set(property: "item_count",    value: itemCount)
        identify.set(property: "signup_method", value: signupMethod)
        amplitude?.identify(identify: identify)
    }

    /// Call on sign-out to disassociate future events from this user.
    func reset() {
        amplitude?.reset()
    }

    // MARK: - Track

    func track(_ event: StoqlyEvent) {
        guard isConfigured else { return }
        amplitude?.track(
            eventType: event.name,
            eventProperties: event.properties
        )
    }
}

// MARK: - StoqlyEvent

/// Type-safe events. Adding a new event = add a case here. No magic strings elsewhere.
enum StoqlyEvent {

    // ── Auth ────────────────────────────────────────────────────────────────────
    case userSignedUp(method: String)                      // method: "email" | "google"
    case userSignedIn(method: String)
    case userSignedOut

    // ── Storages ─────────────────────────────────────────────────────────────────
    case storageCreated(color: String)
    case storageDeleted
    case storageViewed

    // ── Items ────────────────────────────────────────────────────────────────────
    case itemAdded(category: String, hasBarcode: Bool, hasPhoto: Bool)
    case itemUpdated
    case itemDeleted(category: String)
    case itemCounted(storageName: String)

    // ── Barcode ──────────────────────────────────────────────────────────────────
    case barcodeScanInitiated
    case barcodeScanResult(found: Bool, enriched: Bool)

    // ── Smart Count / AI ─────────────────────────────────────────────────────────
    case smartCountOpened
    case smartCountModeSelected(mode: String)              // "voice" | "photo" | "sheet"
    case smartCountCompleted(mode: String, itemCount: Int)
    case smartCountFailed(mode: String, reason: String)

    // ── Bulk Import ──────────────────────────────────────────────────────────────
    case bulkImportCompleted(itemCount: Int, format: String)  // format: "csv" | "xlsx"
    case bulkImportFailed(reason: String)

    // ── Monetisation ─────────────────────────────────────────────────────────────
    case paywallShown(source: String)                      // source: "storage_limit" | "item_limit" | "pro_feature" | "ai_limit"
    case subscriptionStarted(plan: String)                 // plan: "monthly" | "annual"
    case subscriptionCancelled
    case removeAdsPurchased
    case restorePurchaseTapped

    // ── Key Screens ──────────────────────────────────────────────────────────────
    case dashboardViewed
    case reorderListViewed(itemCount: Int)
    case expiryTimelineViewed(itemCount: Int)
    case categoryExplorerViewed
    case settingsViewed
    case exportCompleted(format: String)                   // "csv" | "pdf"

    // ── Errors / Crashes (non-fatal, for awareness) ───────────────────────────────
    case syncFailed(reason: String)
    case barcodeEnrichmentFailed

    // MARK: Event name + properties

    var name: String {
        switch self {
        case .userSignedUp:              return "user_signed_up"
        case .userSignedIn:              return "user_signed_in"
        case .userSignedOut:             return "user_signed_out"

        case .storageCreated:            return "storage_created"
        case .storageDeleted:            return "storage_deleted"
        case .storageViewed:             return "storage_viewed"

        case .itemAdded:                 return "item_added"
        case .itemUpdated:               return "item_updated"
        case .itemDeleted:               return "item_deleted"
        case .itemCounted:               return "item_counted"

        case .barcodeScanInitiated:      return "barcode_scan_initiated"
        case .barcodeScanResult:         return "barcode_scan_result"

        case .smartCountOpened:          return "smart_count_opened"
        case .smartCountModeSelected:    return "smart_count_mode_selected"
        case .smartCountCompleted:       return "smart_count_completed"
        case .smartCountFailed:          return "smart_count_failed"

        case .bulkImportCompleted:       return "bulk_import_completed"
        case .bulkImportFailed:          return "bulk_import_failed"

        case .paywallShown:              return "paywall_shown"
        case .subscriptionStarted:       return "subscription_started"
        case .subscriptionCancelled:     return "subscription_cancelled"
        case .removeAdsPurchased:        return "remove_ads_purchased"
        case .restorePurchaseTapped:     return "restore_purchase_tapped"

        case .dashboardViewed:           return "dashboard_viewed"
        case .reorderListViewed:         return "reorder_list_viewed"
        case .expiryTimelineViewed:      return "expiry_timeline_viewed"
        case .categoryExplorerViewed:    return "category_explorer_viewed"
        case .settingsViewed:            return "settings_viewed"
        case .exportCompleted:           return "export_completed"

        case .syncFailed:                return "sync_failed"
        case .barcodeEnrichmentFailed:   return "barcode_enrichment_failed"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .userSignedUp(let method):       return ["method": method]
        case .userSignedIn(let method):       return ["method": method]
        case .userSignedOut:                  return [:]

        case .storageCreated(let color):      return ["color": color]
        case .storageDeleted:                 return [:]
        case .storageViewed:                  return [:]

        case .itemAdded(let cat, let bar, let photo):
            return ["category": cat, "has_barcode": bar, "has_photo": photo]
        case .itemUpdated:                    return [:]
        case .itemDeleted(let cat):           return ["category": cat]
        case .itemCounted(let s):             return ["storage_name": s]

        case .barcodeScanInitiated:           return [:]
        case .barcodeScanResult(let f, let e):return ["found": f, "enriched": e]

        case .smartCountOpened:               return [:]
        case .smartCountModeSelected(let m):  return ["mode": m]
        case .smartCountCompleted(let m, let n):
            return ["mode": m, "item_count": n]
        case .smartCountFailed(let m, let r): return ["mode": m, "reason": r]

        case .bulkImportCompleted(let n, let fmt):
            return ["item_count": n, "format": fmt]
        case .bulkImportFailed(let r):        return ["reason": r]

        case .paywallShown(let src):          return ["source": src]
        case .subscriptionStarted(let plan):  return ["plan": plan]
        case .subscriptionCancelled:          return [:]
        case .removeAdsPurchased:             return [:]
        case .restorePurchaseTapped:          return [:]

        case .dashboardViewed:                return [:]
        case .reorderListViewed(let n):       return ["item_count": n]
        case .expiryTimelineViewed(let n):    return ["item_count": n]
        case .categoryExplorerViewed:         return [:]
        case .settingsViewed:                 return [:]
        case .exportCompleted(let fmt):       return ["format": fmt]

        case .syncFailed(let r):              return ["reason": r]
        case .barcodeEnrichmentFailed:        return [:]
        }
    }
}
