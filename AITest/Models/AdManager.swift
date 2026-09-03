import Foundation
import SwiftUI
#if !targetEnvironment(simulator)
import GoogleMobileAds
#endif

// MARK: - Premium Features Documentation
/*
 PREMIUM FEATURES - To be implemented via SubscriptionManager (StoreKit 2)

 Free Tier (Ad-supported):
 - Up to 5 storage areas
 - Unlimited items
 - CSV export
 - Basic dashboard

 Pro Tier (StoreKit localized price, no free trial):
 1. Cloud Sync & Backup       — Firestore real-time sync, multi-device
 2. Unlimited Storages        — Remove 5-storage free limit
 3. Advanced Analytics        — Trend charts, detailed reports
 4. PDF Export                — Branded PDF reports
  5. Barcode Scanner Pro       — Bulk scan (camera stays open), then save all
 6. Push Notifications        — Low-stock alerts via FCM
 7. Multi-User Collaboration  — Invite team members
 8. AI Reorder Suggestions    — Demand forecasting
 9. Remove Ads                — Ad-free experience
 10. API Integration          — Webhooks, CSV import

*/

/// Wraps a non-Sendable ObjC ad object so it can safely cross actor boundaries.
/// Safe because we immediately hand ownership to the main actor and never share it.
private struct SendableAd<T>: @unchecked Sendable { let value: T }

@MainActor
class AdManager: NSObject, ObservableObject {
    @Published var shouldShowAd = false
    @Published var currentAdType: AdType = .interstitial
    @Published var isAdLoading = false
    @Published var adLoadError: String?
    @Published var isInitialized = false

    // MARK: - Live Ad Unit IDs (replace if you create new units in AdMob console)
    let bannerAdUnitID       = "ca-app-pub-9489340523484530/3501995184"
    let interstitialAdUnitID = "ca-app-pub-9489340523484530/1789458261"

    // MARK: - Test Ad Unit IDs (safe for development — never triggers policy violations)
    private let testBannerUnitID       = "ca-app-pub-3940256099942544/2934735716"
    private let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    #if targetEnvironment(simulator)
    private var interstitialAd: Any?
    #else
    private var interstitialAd: GADInterstitialAd?
    #endif

    private var completionCount = 0
    private var lastAdShown = Date.distantPast
    private let minTimeBetweenAds: TimeInterval = 300  // 5 minutes between ads
    private let actionsBeforeAd = 2                    // Show ad every 2 workflow actions

    /// Last screen/event that triggered a banner mount (for ad_* source_screen).
    var bannerSourceScreen: String = "banner_overlay"
    private var interstitialSourceScreen: String = "app_launch"
    private var lastInterstitialUnitID: String = ""
    private var interstitialRequestStartedAt: Date?
    private var interstitialPresentedAt: Date?

    // MARK: - Enums

    enum AdType {
        case interstitial
        case banner
    }

    enum CompletionEvent {
        case storageCreated
        case itemAdded
        case inventoryCountCompleted
        case itemUpdated
        case storageUpdated
        case exportCompleted
        case barcodeScanned
        case bulkImportCompleted
    }

    // MARK: - Singleton

    static let shared = AdManager()

    private override init() {
        super.init()
        // AdMob initialization is deferred until ATT permission is resolved.
        // Call initializeAfterTrackingDecision() from TrackingPermissionManager.
    }

    // MARK: - Initialization

    /// Called by TrackingPermissionManager after the user responds to the ATT prompt.
    /// Safe to call multiple times — guards against double-initialization.
    func initializeAfterTrackingDecision() {
        guard !isInitialized else { return }

        #if targetEnvironment(simulator)
        print("AdMob: Simulator detected — ads are simulated, no real SDK calls.")
        isInitialized = true
        return
        #else
        // The GADApplicationIdentifier must be set in Xcode:
        // Target → Info → Custom iOS Target Properties → GADApplicationIdentifier
        // Value: ca-app-pub-9489340523484530~5027045442
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
              !appID.isEmpty else {
            print("""
            ⚠️  AdMob DISABLED: GADApplicationIdentifier missing from Info.plist.
            Fix: Xcode → Target → Info → Custom iOS Target Properties
            Add key: GADApplicationIdentifier
            Value:   ca-app-pub-9489340523484530~5027045442
            """)
            return
        }

        GADMobileAds.sharedInstance().start { [weak self] status in
            // Extract the Sendable string before crossing into the main actor.
            let adapterKeys = status.adapterStatusesByClassName.keys.joined(separator: ", ")
            Task { @MainActor [weak self] in
                self?.isInitialized = true
                print("AdMob: SDK initialized. Adapter statuses: \(adapterKeys)")
                if SubscriptionManager.shared.shouldShowAds {
                    self?.preloadInterstitialAd()
                }
            }
        }

        // Configure test devices in DEBUG so we never accidentally generate
        // invalid traffic on real devices during development.
        // To add your physical device: run the app, copy the hash from the Xcode console
        // (look for "To get test ads on this device, set testDeviceIdentifiers = [...]"),
        // then call AdManager.shared.addTestDevice("YOUR_HASH_HERE") from AppDelegate.
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            // "YOUR_DEVICE_HASH_HERE"
        ]
        print("AdMob: Test mode active for DEBUG build.")
        #endif
        #endif
    }

    // MARK: - Ad Tracking

    func recordCompletion(event: CompletionEvent) {
        #if targetEnvironment(simulator)
        return
        #else
        guard isInitialized else { return }
        // Pro / Remove Ads must never accumulate toward an interstitial.
        // `disableAds()` only clears current state; without this gate the next
        // barcode beep re-opens the overlay.
        guard SubscriptionManager.shared.shouldShowAds else { return }

        completionCount += 1
        if shouldShowAdNow() {
            currentAdType = determineAdType(for: event)
            let screen = sourceScreenName(for: event)
            if currentAdType == .banner {
                bannerSourceScreen = screen
            } else {
                interstitialSourceScreen = screen
            }
            loadAndShowAd()
        }
        #endif
    }

    private func shouldShowAdNow() -> Bool {
        guard SubscriptionManager.shared.shouldShowAds else { return false }
        guard completionCount >= actionsBeforeAd else { return false }
        return Date().timeIntervalSince(lastAdShown) >= minTimeBetweenAds
    }

    private func determineAdType(for event: CompletionEvent) -> AdType {
        switch event {
        case .inventoryCountCompleted, .exportCompleted, .barcodeScanned,
             .itemAdded, .storageCreated, .bulkImportCompleted:
            return .interstitial
        case .storageUpdated, .itemUpdated:
            return .banner
        }
    }

    // MARK: - Ad Loading & Display

    private func loadAndShowAd() {
        guard SubscriptionManager.shared.shouldShowAds else { return }
        switch currentAdType {
        case .interstitial:
            if interstitialAd != nil {
                shouldShowAd = true
                lastAdShown = Date()
                completionCount = 0
            } else {
                loadInterstitialAd()
            }
        case .banner:
            shouldShowAd = true
            lastAdShown = Date()
            completionCount = 0
        }
    }

    private func preloadInterstitialAd() {
        #if !targetEnvironment(simulator)
        guard SubscriptionManager.shared.shouldShowAds else { return }
        let unitID = isLiveBuild ? interstitialAdUnitID : testInterstitialUnitID
        lastInterstitialUnitID = unitID
        interstitialRequestStartedAt = Date()
        emitAdRequested(unitID: unitID, format: "interstitial", sourceScreen: interstitialSourceScreen)
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: unitID, request: request) { [weak self] ad, error in
            let wrapped = ad.map { SendableAd(value: $0) }
            let nsError = error as NSError?
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let nsError {
                    print("AdMob: Interstitial preload failed — \(nsError.localizedDescription)")
                    self.emitAdFailedToLoad(unitID: unitID, format: "interstitial", error: nsError)
                    return
                }
                let latency = self.latencyMs(since: self.interstitialRequestStartedAt)
                self.interstitialAd = wrapped?.value
                self.interstitialAd?.fullScreenContentDelegate = self
                self.emitAdLoaded(unitID: unitID, format: "interstitial", latencyMs: latency)
                print("AdMob: Interstitial preloaded and ready.")
            }
        }
        #endif
    }

    private func loadInterstitialAd() {
        #if !targetEnvironment(simulator)
        guard SubscriptionManager.shared.shouldShowAds else { return }
        isAdLoading = true
        adLoadError = nil

        let unitID = isLiveBuild ? interstitialAdUnitID : testInterstitialUnitID
        lastInterstitialUnitID = unitID
        interstitialRequestStartedAt = Date()
        emitAdRequested(unitID: unitID, format: "interstitial", sourceScreen: interstitialSourceScreen)
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: unitID, request: request) { [weak self] ad, error in
            let wrapped = ad.map { SendableAd(value: $0) }
            let nsError = error as NSError?
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAdLoading = false
                if let nsError {
                    self.adLoadError = nsError.localizedDescription
                    print("AdMob: Interstitial load failed — \(nsError.localizedDescription)")
                    self.emitAdFailedToLoad(unitID: unitID, format: "interstitial", error: nsError)
                    return
                }
                guard SubscriptionManager.shared.shouldShowAds else {
                    self.interstitialAd = nil
                    self.shouldShowAd = false
                    return
                }
                let latency = self.latencyMs(since: self.interstitialRequestStartedAt)
                self.interstitialAd = wrapped?.value
                self.interstitialAd?.fullScreenContentDelegate = self
                self.emitAdLoaded(unitID: unitID, format: "interstitial", latencyMs: latency)
                self.shouldShowAd = true
                self.lastAdShown = Date()
                self.completionCount = 0
            }
        }
        #endif
    }

    // MARK: - Show Ads

    func showInterstitialAd() {
        #if !targetEnvironment(simulator)
        guard SubscriptionManager.shared.shouldShowAds else {
            shouldShowAd = false
            return
        }
        guard let ad = interstitialAd else {
            // No cached ad yet. Kick off a fresh load so there's a better
            // chance next time. Auto-dismiss the cover immediately — don't
            // make the user click through a "no ad" error screen.
            print("AdMob: Interstitial not ready — preloading for next opportunity.")
            preloadInterstitialAd()
            // Dismiss the overlay without showing an error.
            shouldShowAd = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            shouldShowAd = false
            return
        }
        // Nil out immediately — GAD interstitials can only be presented once.
        // Keeping a reference after presentation causes a stale-ad bug where
        // the next cycle finds interstitialAd != nil, opens the cover, and then
        // AdMob silently fails to present, showing the "Ad unavailable" error.
        interstitialAd = nil
        ad.present(fromRootViewController: root)
        #endif
    }

    // MARK: - Controls

    func dismissAd() {
        shouldShowAd = false
        adLoadError = nil
        isAdLoading = false
        // Pre-load next interstitial so it's ready
        preloadInterstitialAd()
    }

    func disableAds() {
        completionCount = 0
        shouldShowAd = false
        isAdLoading = false
        adLoadError = nil
        interstitialAd = nil
    }

    // MARK: - Debug / Testing

    func showTestAd(type: AdType = .interstitial) {
        currentAdType = type
        switch type {
        case .interstitial:
            interstitialSourceScreen = "settings_debug"
            loadInterstitialAd()
        case .banner:
            bannerSourceScreen = "settings_debug"
            shouldShowAd = true
        }
    }

    func addTestDevice(_ deviceID: String) {
        #if !targetEnvironment(simulator)
        var devices = GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers ?? []
        guard !devices.contains(deviceID) else { return }
        devices.append(deviceID)
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = devices
        print("AdMob: Test device added — \(deviceID)")
        #endif
    }

    func getTestDeviceIDs() -> [String] {
        #if !targetEnvironment(simulator)
        return GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers ?? []
        #else
        return ["Simulator"]
        #endif
    }

    // MARK: - Helpers

    private var isLiveBuild: Bool {
        #if DEBUG
        return false  // Use test ad unit IDs in debug
        #else
        return true   // Use live ad unit IDs in release
        #endif
    }

    private func sourceScreenName(for event: CompletionEvent) -> String {
        switch event {
        case .storageCreated: return "storage_created"
        case .itemAdded: return "item_added"
        case .inventoryCountCompleted: return "inventory_count"
        case .itemUpdated: return "item_updated"
        case .storageUpdated: return "storage_updated"
        case .exportCompleted: return "export"
        case .barcodeScanned: return "barcode_scan"
        case .bulkImportCompleted: return "bulk_import"
        }
    }

    private func latencyMs(since start: Date?) -> Int {
        guard let start else { return 0 }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Dashboard / ItemList call this on appear. Fires `ad_requested` so Amplitude
    /// can distinguish entitlement suppression from actual AdMob fill. Does not
    /// change whether a banner is mounted.
    func noteBannerOpportunity(sourceScreen: String) {
        let suppressed = !SubscriptionManager.shared.shouldShowAds
        emitAdRequested(unitID: bannerAdUnitID, format: "banner", sourceScreen: sourceScreen)
        printAdDecisionTree(sourceScreen: sourceScreen, format: "banner", suppressed: suppressed)
        #if DEBUG && targetEnvironment(simulator)
        if !suppressed {
            // Simulator never calls the GMA SDK; emit failed_to_load so the
            // Xcode console probe has a complete request → result pair.
            emitAdFailedToLoad(
                unitID: bannerAdUnitID,
                format: "banner",
                error: NSError(
                    domain: "simulator",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "AdMob SDK is skipped on simulator"]
                )
            )
        }
        #endif
    }

    func emitAdRequested(unitID: String, format: String, sourceScreen: String) {
        AnalyticsManager.shared.track(.adRequested(
            unitId: unitID,
            format: format,
            sourceScreen: sourceScreen,
            isPro: SubscriptionManager.shared.isPro,
            suppressed: !SubscriptionManager.shared.shouldShowAds
        ))
    }

    func emitAdLoaded(unitID: String, format: String, latencyMs: Int) {
        AnalyticsManager.shared.track(.adLoaded(unitId: unitID, format: format, latencyMs: latencyMs))
    }

    func emitAdFailedToLoad(unitID: String, format: String, error: NSError) {
        AnalyticsManager.shared.track(.adFailedToLoad(
            unitId: unitID,
            format: format,
            errorCode: error.code,
            errorDomain: error.domain,
            errorLocalized: error.localizedDescription
        ))
    }

    func emitAdImpression(unitID: String, format: String, sourceScreen: String) {
        AnalyticsManager.shared.track(.adImpression(unitId: unitID, format: format, sourceScreen: sourceScreen))
    }

    func emitAdClicked(unitID: String, format: String, sourceScreen: String) {
        AnalyticsManager.shared.track(.adClicked(unitId: unitID, format: format, sourceScreen: sourceScreen))
    }

    func emitAdDismissed(unitID: String, format: String, dwellMs: Int) {
        AnalyticsManager.shared.track(.adDismissed(unitId: unitID, format: format, dwellMs: dwellMs))
    }

    private func printAdDecisionTree(sourceScreen: String, format: String, suppressed: Bool) {
        #if DEBUG
        let mounted = shouldShowAd && currentAdType == .banner
        NSLog("📊 [iOS-F4] Ad decision tree source=%@ format=%@ isInitialized=%d isPro=%d hasRemovedAds=%d shouldShowAds=%d suppressed=%d shouldShowAd=%d currentAdType=%@ bannerMounted=%d completionCount=%d attResolved=%d attAuthorized=%d",
              sourceScreen,
              format,
              isInitialized,
              SubscriptionManager.shared.isPro,
              SubscriptionManager.shared.hasRemovedAds,
              SubscriptionManager.shared.shouldShowAds,
              suppressed,
              shouldShowAd,
              String(describing: currentAdType),
              mounted,
              completionCount,
              TrackingPermissionManager.shared.hasResolved,
              TrackingPermissionManager.shared.isAuthorized)
        #endif
    }
}

// MARK: - GADFullScreenContentDelegate

#if !targetEnvironment(simulator)
@MainActor
extension AdManager: @preconcurrency GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        let dwell = latencyMs(since: interstitialPresentedAt)
        interstitialPresentedAt = nil
        emitAdDismissed(unitID: lastInterstitialUnitID, format: "interstitial", dwellMs: dwell)
        shouldShowAd = false
        preloadInterstitialAd()
        print("AdMob: Ad dismissed — preloading next.")
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let nsError = error as NSError
        emitAdFailedToLoad(unitID: lastInterstitialUnitID, format: "interstitial", error: nsError)
        shouldShowAd = false
        adLoadError = nil
        interstitialAd = nil
        print("AdMob: Ad failed to present — \(error.localizedDescription)")
        preloadInterstitialAd()
    }

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        interstitialPresentedAt = Date()
        print("AdMob: Ad presenting full screen.")
    }

    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        emitAdImpression(unitID: lastInterstitialUnitID, format: "interstitial", sourceScreen: interstitialSourceScreen)
    }

    func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        emitAdClicked(unitID: lastInterstitialUnitID, format: "interstitial", sourceScreen: interstitialSourceScreen)
    }
}
#endif

// MARK: - Banner Ad View

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    var sourceScreen: String = "banner_overlay"

    #if !targetEnvironment(simulator)
    func makeCoordinator() -> Coordinator {
        Coordinator(adUnitID: adUnitID, sourceScreen: sourceScreen)
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            banner.rootViewController = root
        }
        context.coordinator.requestedAt = Date()
        AdManager.shared.emitAdRequested(unitID: adUnitID, format: "banner", sourceScreen: sourceScreen)
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}

    final class Coordinator: NSObject, GADBannerViewDelegate {
        let adUnitID: String
        let sourceScreen: String
        var requestedAt = Date()
        var presentedAt: Date?

        init(adUnitID: String, sourceScreen: String) {
            self.adUnitID = adUnitID
            self.sourceScreen = sourceScreen
        }

        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            let latency = Int(Date().timeIntervalSince(requestedAt) * 1000)
            Task { @MainActor [adUnitID] in
                AdManager.shared.emitAdLoaded(unitID: adUnitID, format: "banner", latencyMs: latency)
            }
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            let nsError = error as NSError
            Task { @MainActor [adUnitID] in
                AdManager.shared.emitAdFailedToLoad(unitID: adUnitID, format: "banner", error: nsError)
            }
        }

        func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
            Task { @MainActor [adUnitID, sourceScreen] in
                AdManager.shared.emitAdImpression(unitID: adUnitID, format: "banner", sourceScreen: sourceScreen)
            }
        }

        func bannerViewDidRecordClick(_ bannerView: GADBannerView) {
            Task { @MainActor [adUnitID, sourceScreen] in
                AdManager.shared.emitAdClicked(unitID: adUnitID, format: "banner", sourceScreen: sourceScreen)
            }
        }

        func bannerViewWillPresentScreen(_ bannerView: GADBannerView) {
            presentedAt = Date()
        }

        func bannerViewDidDismissScreen(_ bannerView: GADBannerView) {
            let dwell = presentedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            presentedAt = nil
            Task { @MainActor [adUnitID] in
                AdManager.shared.emitAdDismissed(unitID: adUnitID, format: "banner", dwellMs: dwell)
            }
        }
    }

    #else
    func makeUIView(context: Context) -> UIView {
        AdManager.shared.emitAdRequested(unitID: adUnitID, format: "banner", sourceScreen: sourceScreen)
        AdManager.shared.emitAdFailedToLoad(
            unitID: adUnitID,
            format: "banner",
            error: NSError(
                domain: "simulator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AdMob SDK is skipped on simulator"]
            )
        )
        let view = UIView()
        view.backgroundColor = UIColor.systemGray5
        let label = UILabel()
        label.text = "Ad Placeholder (Simulator)"
        label.textColor = .systemGray
        label.font = .systemFont(ofSize: 12)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    #endif
}

// MARK: - Interstitial Ad Trigger View

struct InterstitialAdTrigger: View {
    @ObservedObject var adManager: AdManager
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 20) {
                if adManager.isAdLoading {
                    ProgressView("Loading ad...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                } else if let error = adManager.adLoadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Ad unavailable")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                        Text("No ad to show")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }

                Button(action: close) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear {
            if adManager.shouldShowAd && adManager.currentAdType == .interstitial {
                adManager.showInterstitialAd()
            }
            // Safety net: if nothing has happened in 5 seconds (AdMob didn't
            // present OR dismiss), auto-escape so the user is never stuck.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if adManager.shouldShowAd {
                    close()
                }
            }
        }
    }

    private func close() {
        // Reset ad state first so syncInterstitialOverlay() finds shouldShowAd=false
        // and treats the upcoming binding change as a no-op (avoids double-dismiss).
        adManager.dismissAd()
        // Tell the parent to set showInterstitialOverlay = false.
        // This is the single dismiss path — do NOT also call dismiss() here.
        // Calling dismiss() while also changing the isPresented binding causes
        // SwiftUI to conflict-cancel the animation and the cover stays on screen.
        onDismiss()
    }
}

// MARK: - Ad Integration Container

/// Wrap your main content in this view to automatically handle
/// banner and interstitial ads based on user actions.
struct RealAdIntegrationView<Content: View>: View {
    @ObservedObject private var adManager = AdManager.shared
    @State private var showInterstitialOverlay = false
    @State private var showUpgradeChip = false
    @ViewBuilder let content: Content

    private let teal = Color(red: 0.051, green: 0.580, blue: 0.533)
    private let navy = Color(red: 0.031, green: 0.098, blue: 0.173)

    var body: some View {
        ZStack {
            content

            // Persistent banner ad — shown above the tab bar when triggered
            if adManager.shouldShowAd && adManager.currentAdType == .banner && SubscriptionManager.shared.shouldShowAds {
                VStack {
                    Spacer()
                    BannerAdView(adUnitID: adManager.bannerAdUnitID, sourceScreen: adManager.bannerSourceScreen)
                        .frame(height: 50)
                        .padding(.bottom, 90) // clear the custom tab bar
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: adManager.shouldShowAd)
            }

            // Post-interstitial upsell chip — slides up for 3.5 s after ad dismissal
            if showUpgradeChip && !SubscriptionManager.shared.isPro {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Remove Ads — Go Pro")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("Upgrade")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(navy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 96) // clear tab bar
                    .onTapGesture {
                        showUpgradeChip = false
                        NotificationCenter.default.post(
                            name: NSNotification.Name("stoqly.showPaywall"),
                            object: nil
                        )
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: showUpgradeChip)
                .zIndex(10)
            }
        }
        .onChange(of: adManager.shouldShowAd) { _, _ in
            syncInterstitialOverlay()
        }
        .onChange(of: adManager.currentAdType) { _, _ in
            syncInterstitialOverlay()
        }
        .onAppear {
            syncInterstitialOverlay()
        }
        // onDismiss: fires on EVERY cover dismissal — whether the user tapped
        // "Continue" on the fallback screen OR AdMob's native ad self-dismissed.
        // This is the single place for post-interstitial logic (upsell chip).
        .fullScreenCover(isPresented: $showInterstitialOverlay, onDismiss: {
            guard !SubscriptionManager.shared.isPro else { return }
            withAnimation { showUpgradeChip = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { showUpgradeChip = false }
            }
        }) {
            // onDismiss closure just sets the binding — the fullScreenCover's
            // own onDismiss: (above) handles all post-dismiss side-effects.
            InterstitialAdTrigger(adManager: adManager) {
                showInterstitialOverlay = false
            }
        }
    }

    private func syncInterstitialOverlay() {
        guard SubscriptionManager.shared.shouldShowAds else {
            showInterstitialOverlay = false
            return
        }
        showInterstitialOverlay = adManager.shouldShowAd && adManager.currentAdType == .interstitial
    }
}
