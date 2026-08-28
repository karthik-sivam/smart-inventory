import Foundation
import AmplitudeSwift
import Network
import UIKit

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
    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.isOffline = path.status != .satisfied
        }
        pathMonitor.start(queue: pathQueue)
        Task { @MainActor [weak self] in
            self?.cachedDeviceClass = Self.deviceClassOnMain()
        }
    }

    private var amplitude: Amplitude?
    private var isConfigured = false
    private let fallbackSessionId = UUID().uuidString
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "stoqly.analytics.path")
    private var isOffline = false
    private var cachedDeviceClass = "phone"

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

    /// Call after sign-in, on auth-state restore, or whenever user properties change.
    /// Only non-nil properties are written, so calling this on app launch (without
    /// counts/method) won't overwrite previously-set values. `signup_method` uses
    /// setOnce so it's never clobbered after the first sign-up.
    func identify(
        userId: String,
        email: String? = nil,
        isPro: Bool,
        storageCount: Int? = nil,
        itemCount: Int? = nil,
        signupMethod: String? = nil
    ) {
        amplitude?.setUserId(userId: userId)
        let identify = Identify()
        if let email = email { identify.set(property: "email", value: email) }
        identify.set(property: "is_pro", value: isPro)
        if let storageCount = storageCount { identify.set(property: "storage_count", value: storageCount) }
        if let itemCount = itemCount { identify.set(property: "item_count", value: itemCount) }
        if let signupMethod = signupMethod { identify.setOnce(property: "signup_method", value: signupMethod) }
        amplitude?.identify(identify: identify)
    }

    /// Call on sign-out to disassociate future events from this user.
    func reset() {
        amplitude?.reset()
    }

    // MARK: - Track

    func track(_ event: StoqlyEvent) {
        var props = event.properties
        for (key, value) in standardProperties() {
            if props[key] == nil {
                props[key] = value
            }
        }
        #if DEBUG
        if event.isAdLifecycleEvent {
            // TODO(iOS-F4): remove this debug print after CEO sees the first Amplitude reads
            NSLog("📊 [iOS-F4] Amplitude event: \(event.name) \(props)")
        }
        #endif
        guard isConfigured else { return }
        amplitude?.track(
            eventType: event.name,
            eventProperties: props
        )
    }

    // MARK: - Standard properties (docs/event-taxonomy.md)

    private func standardProperties() -> [String: Any] {
        [
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "platform": "ios",
            "is_offline": isOffline,
            "device_class": cachedDeviceClass,
            "session_id": sessionIdString
        ]
    }

    private var sessionIdString: String {
        if let amplitude {
            return String(amplitude.getSessionId())
        }
        return fallbackSessionId
    }

    @MainActor
    private static func deviceClassOnMain() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "tablet"
        case .phone: return "phone"
        default: return "other"
        }
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
    case itemAdded(category: String, hasBarcode: Bool, hasPhoto: Bool, source: String, inputMethod: String)
    case itemUpdated
    case itemDeleted(category: String)
    case itemCounted(storageName: String)

    // ── Barcode ──────────────────────────────────────────────────────────────────
    case barcodeScanInitiated
    case barcodeScanResult(
        outcome: String,
        provider: String,
        symbology: String?,
        code: String?,          // commercial product ID (EAN/UPC/ISBN/GTIN) — not PII; never omit when a code was read
        durationMs: Int,
        reason: String?
    )

    // ── Smart Count / AI ─────────────────────────────────────────────────────────
    case smartCountOpened
    case smartCountModeSelected(mode: String)              // "voice" | "photo" | "sheet"
    case smartCountCompleted(mode: String, itemCount: Int, capturedExtraFields: [String]?)
    case smartCountFailed(mode: String, reason: String)

    // ── AI request terminals (iOS-D1b) ───────────────────────────────────────────
    // One started → exactly one of succeeded / empty / failed per model call.
    // feature: voice_count | voice_sales | photo_count | photo_sales | sheet_count
    //          | sheet_sales | sheet_import | identify_product | ask_ai_help
    case aiRequestStarted(feature: String, mode: String?, inputSizeKB: Int?)
    case aiRequestSucceeded(feature: String, mode: String?, itemCount: Int, durationMs: Int, provider: String)
    case aiRequestEmpty(feature: String, mode: String?, durationMs: Int, reason: String)
    case aiRequestFailed(feature: String, mode: String?, stage: String, errorClass: String, reason: String, durationMs: Int?)

    // ── Bulk Import ──────────────────────────────────────────────────────────────
    case bulkImportCompleted(itemCount: Int, format: String)  // format: "csv" | "xlsx"
    case bulkImportFailed(reason: String)

    // ── Monetisation ─────────────────────────────────────────────────────────────
    case paywallShown(source: String, trigger: String?)              // source: limit/feature; trigger: optional detail
    case subscriptionStarted(plan: String)                 // plan: "monthly" | "annual"
    case subscriptionCancelled
    case removeAdsPurchased
    case restorePurchaseTapped

    // ── Free trial lifecycle (iOS-F1) ────────────────────────────────────────────
    // plan is "monthly" | "yearly". These sit ALONGSIDE paywall_shown /
    // paywall_cta_tapped / subscription_started — none of those changed.
    case trialStarted(plan: String, endsAt: Date, source: String)
    case trialConverted(plan: String, daysUsed: Int)      // trial rolled into paid
    case trialCancelled(plan: String, daysUsed: Int)      // auto-renew off before expiry
    case trialExpired(plan: String)                       // window closed, no conversion

    // ── Key Screens ──────────────────────────────────────────────────────────────
    case dashboardViewed
    case reorderListViewed(itemCount: Int)
    case expiryTimelineViewed(itemCount: Int)
    case categoryExplorerViewed
    case settingsViewed
    case exportCompleted(format: String)                   // "csv" | "pdf"
    case exportFailed(format: String, reason: String)      // iOS-D1d; pair with exportCompleted

    // ── Sales & Movements (Phase 7A) ─────────────────────────────────────────────
    case saleRecorded(itemId: String, qty: Double, sellingPrice: Double, costPrice: Double, profit: Double, storageId: String, mode: String)
    case movementLogged(itemId: String, movementType: String, qty: Double, pricePerUnit: Double)
    case saleReversed(itemId: String, quantity: Double)
    case movementReversed(itemId: String, movementType: String)
    case reportViewed(period: String)

    // ── Smart Sales Entry (Phase 7B-B) ───────────────────────────────────────────
    case smartSalesOpened
    case smartSalesModeSelected(mode: String)
    case smartSalesCompleted(mode: String, saleCount: Int)
    case smartSalesFailed(mode: String, reason: String)  // iOS-D1b; parity with smartCountFailed

    // ── Sync (iOS-D1d) ────────────────────────────────────────────────────────────
    // Session pair on pullFromCloud / background flush. context:
    //   "cold_launch" | "foreground" | "manual" | "background_task"
    // Per-document write failures keep firing syncFailed with context "write"
    // (no started) so queued retries stay diagnosable.
    case syncStarted(context: String)
    case syncCompleted(context: String, docsUpdated: Int, durationMs: Int)
    case syncFailed(context: String, errorClass: String, reason: String, durationMs: Int?)

    // ── Journey backbone (S24) ───────────────────────────────────────────────────
    case screenViewed(name: String, referrer: String?)

    // ── Dashboard taps (S24) ────────────────────────────────────────────────────
    case dashboardCardTapped(card: String)
    case dashboardInsightTapped(insight: String)
    case dashboardTipTapped(tip: String)
    case dashboardPeriodChanged(period: String)
    case viewFullReportTapped
    case floatingAIButtonTapped

    // ── Upgrade / paywall interaction (S24) ──────────────────────────────────────
    case upgradeCtaTapped(source: String)
    case paywallCtaTapped(plan: String)
    case paywallDismissed

    // ── Flow START events (S24) ──────────────────────────────────────────────────
    case addItemStarted(source: String)
    case addItemMoreDetailsToggled(context: String, expanded: Bool) // context: "add_item" | "edit_item"
    case saleEntryStarted(mode: String)
    case purchaseEntryStarted(mode: String)

    // ── Flow terminal events (iOS-D1c) ──────────────────────────────────────────
    case addItemCompleted(source: String, hasBarcode: Bool, hasPhoto: Bool, durationMs: Int)
    case addItemAbandoned(source: String, stage: String, secondsInForm: Int)
    case saleEntryCompleted(mode: String, itemCount: Int, durationMs: Int)
    case saleEntryAbandoned(mode: String, stage: String)
    case purchaseEntryCompleted(mode: String, itemCount: Int, durationMs: Int)
    case purchaseEntryAbandoned(mode: String, stage: String)
    case restorePurchaseResult(outcome: String, restoredCount: Int, reason: String?)
    case trialStartFailed(plan: String, errorClass: String, reason: String)

    // ── Onboarding funnel (S24) ──────────────────────────────────────────────────
    case onboardingStarted
    case onboardingStepViewed(step: Int, name: String)
    case onboardingCompleted
    case onboardingSkipped(step: Int)

    // ── Blockers (S24) ───────────────────────────────────────────────────────────
    case permissionResult(type: String, granted: Bool)
    case emptyStateShown(screen: String)

    // ── Engagement depth (S24) ───────────────────────────────────────────────────
    case searchPerformed(scope: String, resultCount: Int)
    case filterApplied(screen: String, filter: String)
    case languageChanged(toLanguage: String)
    case aiHelpQuestionAsked(question: String)
    case reorderEmailSent(supplierCount: Int, itemCount: Int)
    case reorderEmailFailed(reason: String)                // iOS-D1d; pair with reorderEmailSent
    case voiceEngineUsed(engine: String, language: String)
    case languageChosenAtOnboarding(language: String)
    case feedbackSubmitted(type: String)
    case feedbackPromptShown
    case feedbackPromptTapped
    case feedbackPromptDismissed

    // ── S37: Symmetric open/close + intent events ────────────────────────────────
    case sheetOpened(sheet: String, source: String?)
    case sheetClosed(sheet: String, outcome: String, seconds: Int?)
    case proLockTapped(feature: String)
    case formSubmitAttempted(form: String, valid: Bool, reason: String?)
    case addItemCancelled(source: String, seconds: Int)
    case smartCountCancelled(mode: String?)
    case smartSalesCancelled(mode: String?)
    case saleEntryCancelled(mode: String)
    case purchaseEntryCancelled(mode: String)
    case swipeActionUsed(screen: String, action: String)
    case buttonTapped(screen: String, control: String)
    case aiEntryChipShown(screen: String, feature: String)
    case aiEntryChipTapped(screen: String, feature: String)

    // ── AdMob lifecycle (iOS-F4) ───────────────────────────────────────────────
    case adRequested(unitId: String, format: String, sourceScreen: String, isPro: Bool, suppressed: Bool)
    case adLoaded(unitId: String, format: String, latencyMs: Int)
    case adFailedToLoad(unitId: String, format: String, errorCode: Int, errorDomain: String, errorLocalized: String)
    case adImpression(unitId: String, format: String, sourceScreen: String)
    case adClicked(unitId: String, format: String, sourceScreen: String)
    case adDismissed(unitId: String, format: String, dwellMs: Int)

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

        case .aiRequestStarted:          return "ai_request_started"
        case .aiRequestSucceeded:        return "ai_request_succeeded"
        case .aiRequestEmpty:            return "ai_request_empty"
        case .aiRequestFailed:           return "ai_request_failed"

        case .bulkImportCompleted:       return "bulk_import_completed"
        case .bulkImportFailed:          return "bulk_import_failed"

        case .paywallShown:              return "paywall_shown"
        case .subscriptionStarted:       return "subscription_started"
        case .subscriptionCancelled:     return "subscription_cancelled"
        case .removeAdsPurchased:        return "remove_ads_purchased"
        case .restorePurchaseTapped:     return "restore_purchase_tapped"

        case .trialStarted:              return "trial_started"
        case .trialConverted:            return "trial_converted"
        case .trialCancelled:            return "trial_cancelled"
        case .trialExpired:              return "trial_expired"

        case .dashboardViewed:           return "dashboard_viewed"
        case .reorderListViewed:         return "reorder_list_viewed"
        case .expiryTimelineViewed:      return "expiry_timeline_viewed"
        case .categoryExplorerViewed:    return "category_explorer_viewed"
        case .settingsViewed:            return "settings_viewed"
        case .exportCompleted:           return "export_completed"
        case .exportFailed:              return "export_failed"

        case .saleRecorded:              return "sale_recorded"
        case .movementLogged:            return "movement_logged"
        case .saleReversed:              return "sale_reversed"
        case .movementReversed:          return "movement_reversed"
        case .reportViewed:              return "report_viewed"

        case .smartSalesOpened:          return "smart_sales_opened"
        case .smartSalesModeSelected:    return "smart_sales_mode_selected"
        case .smartSalesCompleted:       return "smart_sales_completed"
        case .smartSalesFailed:          return "smart_sales_failed"

        case .syncStarted:               return "sync_started"
        case .syncCompleted:             return "sync_completed"
        case .syncFailed:                return "sync_failed"

        case .screenViewed:              return "screen_viewed"

        case .dashboardCardTapped:       return "dashboard_card_tapped"
        case .dashboardInsightTapped:    return "dashboard_insight_tapped"
        case .dashboardTipTapped:        return "dashboard_tip_tapped"
        case .dashboardPeriodChanged:    return "dashboard_period_changed"
        case .viewFullReportTapped:      return "view_full_report_tapped"
        case .floatingAIButtonTapped:    return "floating_ai_button_tapped"

        case .upgradeCtaTapped:          return "upgrade_cta_tapped"
        case .paywallCtaTapped:          return "paywall_cta_tapped"
        case .paywallDismissed:          return "paywall_dismissed"

        case .addItemStarted:            return "add_item_started"
        case .addItemMoreDetailsToggled: return "add_item_more_details_toggled"
        case .saleEntryStarted:          return "sale_entry_started"
        case .purchaseEntryStarted:      return "purchase_entry_started"
        case .addItemCompleted:          return "add_item_completed"
        case .addItemAbandoned:          return "add_item_abandoned"
        case .saleEntryCompleted:        return "sale_entry_completed"
        case .saleEntryAbandoned:        return "sale_entry_abandoned"
        case .purchaseEntryCompleted:    return "purchase_entry_completed"
        case .purchaseEntryAbandoned:    return "purchase_entry_abandoned"
        case .restorePurchaseResult:     return "restore_purchase_result"
        case .trialStartFailed:          return "trial_start_failed"

        case .onboardingStarted:         return "onboarding_started"
        case .onboardingStepViewed:       return "onboarding_step_viewed"
        case .onboardingCompleted:       return "onboarding_completed"
        case .onboardingSkipped:         return "onboarding_skipped"

        case .permissionResult:          return "permission_result"
        case .emptyStateShown:           return "empty_state_shown"

        case .searchPerformed:           return "search_performed"
        case .filterApplied:             return "filter_applied"
        case .languageChanged:           return "language_changed"
        case .languageChosenAtOnboarding: return "language_chosen_at_onboarding"
        case .aiHelpQuestionAsked:        return "ai_help_question_asked"
        case .reorderEmailSent:           return "reorder_email_sent"
        case .reorderEmailFailed:         return "reorder_email_failed"
        case .voiceEngineUsed:            return "voice_engine_used"
        case .feedbackSubmitted:          return "feedback_submitted"
        case .feedbackPromptShown:        return "feedback_prompt_shown"
        case .feedbackPromptTapped:       return "feedback_prompt_tapped"
        case .feedbackPromptDismissed:    return "feedback_prompt_dismissed"
        case .sheetOpened:                return "sheet_opened"
        case .sheetClosed:                return "sheet_closed"
        case .proLockTapped:              return "pro_lock_tapped"
        case .formSubmitAttempted:        return "form_submit_attempted"
        case .addItemCancelled:           return "add_item_cancelled"
        case .smartCountCancelled:        return "smart_count_cancelled"
        case .smartSalesCancelled:        return "smart_sales_cancelled"
        case .saleEntryCancelled:         return "sale_entry_cancelled"
        case .purchaseEntryCancelled:     return "purchase_entry_cancelled"
        case .swipeActionUsed:            return "swipe_action_used"
        case .buttonTapped:               return "button_tapped"
        case .aiEntryChipShown:           return "ai_entry_chip_shown"
        case .aiEntryChipTapped:          return "ai_entry_chip_tapped"

        case .adRequested:                return "ad_requested"
        case .adLoaded:                   return "ad_loaded"
        case .adFailedToLoad:             return "ad_failed_to_load"
        case .adImpression:               return "ad_impression"
        case .adClicked:                  return "ad_clicked"
        case .adDismissed:                return "ad_dismissed"
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

        case .itemAdded(let cat, let bar, let photo, let source, let inputMethod):
            return ["category": cat, "has_barcode": bar, "has_photo": photo, "source": source, "input_method": inputMethod]
        case .itemUpdated:                    return [:]
        case .itemDeleted(let cat):           return ["category": cat]
        case .itemCounted(let s):             return ["storage_name": s]

        case .barcodeScanInitiated:           return [:]
        case .barcodeScanResult(let outcome, let provider, let symbology, let code, let durationMs, let reason):
            var props: [String: Any] = [
                "outcome": outcome,
                "provider": provider,
                "duration_ms": durationMs
            ]
            if let symbology, !symbology.isEmpty { props["symbology"] = symbology }
            if let code, !code.isEmpty { props["code"] = code }
            if let reason, !reason.isEmpty { props["reason"] = reason }
            return props

        case .smartCountOpened:               return [:]
        case .smartCountModeSelected(let m):  return ["mode": m]
        case .smartCountCompleted(let m, let n, let fields):
            var props: [String: Any] = ["mode": m, "item_count": n]
            if let fields, !fields.isEmpty {
                props["captured_extra_fields"] = fields
            }
            return props
        case .smartCountFailed(let m, let r): return ["mode": m, "reason": r]

        case .aiRequestStarted(let feature, let mode, let inputSizeKB):
            var props: [String: Any] = ["feature": feature]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            if let inputSizeKB { props["input_size_kb"] = inputSizeKB }
            return props
        case .aiRequestSucceeded(let feature, let mode, let itemCount, let durationMs, let provider):
            var props: [String: Any] = [
                "feature": feature,
                "item_count": itemCount,
                "duration_ms": durationMs,
                "provider": provider
            ]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            return props
        case .aiRequestEmpty(let feature, let mode, let durationMs, let reason):
            var props: [String: Any] = [
                "feature": feature,
                "duration_ms": durationMs,
                "reason": reason
            ]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            return props
        case .aiRequestFailed(let feature, let mode, let stage, let errorClass, let reason, let durationMs):
            var props: [String: Any] = [
                "feature": feature,
                "stage": stage,
                "error_class": errorClass,
                "reason": reason
            ]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            if let durationMs { props["duration_ms"] = durationMs }
            return props

        case .bulkImportCompleted(let n, let fmt):
            return ["item_count": n, "format": fmt]
        case .bulkImportFailed(let r):        return ["reason": r]

        case .paywallShown(let src, let trigger):
            var props: [String: Any] = ["source": src]
            if let trigger, !trigger.isEmpty { props["trigger"] = trigger }
            return props
        case .trialStarted(let plan, let endsAt, let source):
            return [
                "plan": plan,
                "ends_at": ISO8601DateFormatter().string(from: endsAt),
                "source": source
            ]
        case .trialConverted(let plan, let daysUsed):
            return ["plan": plan, "days_used": daysUsed]
        case .trialCancelled(let plan, let daysUsed):
            return ["plan": plan, "days_used": daysUsed]
        case .trialExpired(let plan):
            return ["plan": plan]

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
        case .exportFailed(let fmt, let r):   return ["format": fmt, "reason": r]

        case .saleRecorded(let itemId, let qty, let sp, let cp, let profit, let storageId, let mode):
            return [
                "item_id": itemId,
                "qty": qty,
                "selling_price": sp,
                "cost_price": cp,
                "profit": profit,
                "storage_id": storageId,
                "mode": mode
            ]
        case .movementLogged(let itemId, let type, let qty, let price):
            return ["item_id": itemId, "movement_type": type, "qty": qty, "price_per_unit": price]
        case .saleReversed(let itemId, let quantity):
            return ["item_id": itemId, "quantity": quantity]
        case .movementReversed(let itemId, let movementType):
            return ["item_id": itemId, "movement_type": movementType]
        case .reportViewed(let period):       return ["period": period]

        case .smartSalesOpened:               return [:]
        case .smartSalesModeSelected(let m):  return ["mode": m]
        case .smartSalesCompleted(let m, let n):
            return ["mode": m, "sale_count": n]
        case .smartSalesFailed(let m, let r):
            return ["mode": m, "reason": r]

        case .syncStarted(let context):
            return ["context": context]
        case .syncCompleted(let context, let docs, let durationMs):
            return ["context": context, "docs_updated": docs, "duration_ms": durationMs]
        case .syncFailed(let context, let errorClass, let r, let durationMs):
            var props: [String: Any] = [
                "context": context,
                "error_class": errorClass,
                "reason": r
            ]
            if let durationMs { props["duration_ms"] = durationMs }
            return props

        case .screenViewed(let name, let referrer):
            var props: [String: Any] = ["screen": name]
            if let referrer, !referrer.isEmpty { props["referrer"] = referrer }
            return props

        case .dashboardCardTapped(let card):  return ["card": card]
        case .dashboardInsightTapped(let insight): return ["insight": insight]
        case .dashboardTipTapped(let tip):    return ["tip": tip]
        case .dashboardPeriodChanged(let period): return ["period": period]
        case .viewFullReportTapped:           return [:]
        case .floatingAIButtonTapped:         return [:]

        case .upgradeCtaTapped(let source):  return ["source": source]
        case .paywallCtaTapped(let plan):      return ["plan": plan]
        case .paywallDismissed:               return [:]

        case .addItemStarted(let source):     return ["source": source]
        case .addItemMoreDetailsToggled(let context, let expanded):
            return ["context": context, "expanded": expanded]
        case .saleEntryStarted(let mode):     return ["mode": mode]
        case .purchaseEntryStarted(let mode): return ["mode": mode]
        case .addItemCompleted(let source, let hasBarcode, let hasPhoto, let durationMs):
            return [
                "source": source,
                "has_barcode": hasBarcode,
                "has_photo": hasPhoto,
                "duration_ms": durationMs
            ]
        case .addItemAbandoned(let source, let stage, let secondsInForm):
            return ["source": source, "stage": stage, "seconds_in_form": secondsInForm]
        case .saleEntryCompleted(let mode, let itemCount, let durationMs):
            return ["mode": mode, "item_count": itemCount, "duration_ms": durationMs]
        case .saleEntryAbandoned(let mode, let stage):
            return ["mode": mode, "stage": stage]
        case .purchaseEntryCompleted(let mode, let itemCount, let durationMs):
            return ["mode": mode, "item_count": itemCount, "duration_ms": durationMs]
        case .purchaseEntryAbandoned(let mode, let stage):
            return ["mode": mode, "stage": stage]
        case .restorePurchaseResult(let outcome, let restoredCount, let reason):
            var props: [String: Any] = ["outcome": outcome, "restored_count": restoredCount]
            if let reason, !reason.isEmpty { props["reason"] = reason }
            return props
        case .trialStartFailed(let plan, let errorClass, let reason):
            return ["plan": plan, "error_class": errorClass, "reason": reason]

        case .onboardingStarted:              return [:]
        case .onboardingStepViewed(let step, let name):
            return ["step": step, "step_name": name]
        case .onboardingCompleted:             return [:]
        case .onboardingSkipped(let step):     return ["step": step]

        case .permissionResult(let type, let granted):
            return ["type": type, "granted": granted]
        case .emptyStateShown(let screen):    return ["screen": screen]

        case .searchPerformed(let scope, let resultCount):
            return ["scope": scope, "result_count": resultCount]
        case .filterApplied(let screen, let filter):
            return ["screen": screen, "filter": filter]
        case .languageChanged(let toLanguage):
            return ["to_language": toLanguage]
        case .aiHelpQuestionAsked(let q):
            let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["question": String(text.prefix(500)), "question_length": text.count]
        case .reorderEmailSent(let supplierCount, let itemCount):
            return ["supplier_count": supplierCount, "item_count": itemCount]
        case .reorderEmailFailed(let r):
            return ["reason": r]
        case .voiceEngineUsed(let engine, let language):
            return ["engine": engine, "language": language]
        case .languageChosenAtOnboarding(let language):
            return ["language": language]
        case .feedbackSubmitted(let type):
            return ["type": type]
        case .feedbackPromptShown, .feedbackPromptTapped, .feedbackPromptDismissed:
            return [:]
        case .sheetOpened(let sheet, let source):
            var props: [String: Any] = ["sheet": sheet]
            if let source, !source.isEmpty { props["source"] = source }
            return props
        case .sheetClosed(let sheet, let outcome, let seconds):
            var props: [String: Any] = ["sheet": sheet, "outcome": outcome]
            if let seconds { props["seconds"] = seconds }
            return props
        case .proLockTapped(let feature):
            return ["feature": feature]
        case .formSubmitAttempted(let form, let valid, let reason):
            var props: [String: Any] = ["form": form, "valid": valid]
            if let reason, !reason.isEmpty { props["reason"] = reason }
            return props
        case .addItemCancelled(let source, let seconds):
            return ["source": source, "seconds": seconds]
        case .smartCountCancelled(let mode):
            var props: [String: Any] = [:]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            return props
        case .smartSalesCancelled(let mode):
            var props: [String: Any] = [:]
            if let mode, !mode.isEmpty { props["mode"] = mode }
            return props
        case .saleEntryCancelled(let mode):
            return ["mode": mode]
        case .purchaseEntryCancelled(let mode):
            return ["mode": mode]
        case .swipeActionUsed(let screen, let action):
            return ["screen": screen, "action": action]
        case .buttonTapped(let screen, let control):
            return ["screen": screen, "control": control]
        case .aiEntryChipShown(let screen, let feature),
             .aiEntryChipTapped(let screen, let feature):
            return ["screen": screen, "feature": feature]

        case .adRequested(let unitId, let format, let sourceScreen, let isPro, let suppressed):
            return [
                "unit_id": unitId,
                "format": format,
                "source_screen": sourceScreen,
                "is_pro": isPro,
                "suppressed": suppressed
            ]
        case .adLoaded(let unitId, let format, let latencyMs):
            return ["unit_id": unitId, "format": format, "latency_ms": latencyMs]
        case .adFailedToLoad(let unitId, let format, let errorCode, let errorDomain, let errorLocalized):
            return [
                "unit_id": unitId,
                "format": format,
                "error_code": errorCode,
                "error_domain": errorDomain,
                "error_localized": errorLocalized
            ]
        case .adImpression(let unitId, let format, let sourceScreen):
            return ["unit_id": unitId, "format": format, "source_screen": sourceScreen]
        case .adClicked(let unitId, let format, let sourceScreen):
            return ["unit_id": unitId, "format": format, "source_screen": sourceScreen]
        case .adDismissed(let unitId, let format, let dwellMs):
            return ["unit_id": unitId, "format": format, "dwell_ms": dwellMs]
        }
    }

    /// AdMob lifecycle events that get a temporary DEBUG console dump (iOS-F4).
    var isAdLifecycleEvent: Bool {
        switch self {
        case .adRequested, .adLoaded, .adFailedToLoad, .adImpression, .adClicked, .adDismissed:
            return true
        default:
            return false
        }
    }
}
