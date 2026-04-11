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

 Pro Tier ($4.99/mo or $39.99/yr):
 1. Cloud Sync & Backup       — Firestore real-time sync, multi-device
 2. Unlimited Storages        — Remove 5-storage free limit
 3. Advanced Analytics        — Trend charts, detailed reports
 4. PDF Export                — Branded PDF reports
 5. Barcode Scanner Pro       — Bulk scan, history
 6. Push Notifications        — Low-stock alerts via FCM
 7. Multi-User Collaboration  — Invite team members
 8. AI Reorder Suggestions    — Demand forecasting
 9. Remove Ads                — Ad-free experience
 10. API Integration          — Webhooks, CSV import

 Reward Ads: Unlock 24-hour Pro trial for free users.
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
    let bannerAdUnitID      = "ca-app-pub-9489340523484530/3501995184"
    let interstitialAdUnitID = "ca-app-pub-9489340523484530/1789458261"
    let rewardAdUnitID      = "ca-app-pub-9489340523484530/3557835507"

    // MARK: - Test Ad Unit IDs (safe for development — never triggers policy violations)
    private let testBannerUnitID      = "ca-app-pub-3940256099942544/2934735716"
    private let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    private let testRewardUnitID      = "ca-app-pub-3940256099942544/1712485313"

    #if targetEnvironment(simulator)
    private var interstitialAd: Any?
    private var rewardAd: Any?
    #else
    private var interstitialAd: GADInterstitialAd?
    private var rewardAd: GADRewardedAd?
    #endif

    private var completionCount = 0
    private var lastAdShown = Date.distantPast
    private let minTimeBetweenAds: TimeInterval = 300  // 5 minutes between ads
    private let actionsBeforeAd = 3                    // Show ad every 3 user actions

    // MARK: - Enums

    enum AdType {
        case interstitial
        case banner
        case reward
    }

    enum CompletionEvent {
        case storageCreated
        case itemAdded
        case inventoryCountCompleted
        case settingsChanged
        case itemUpdated
        case storageUpdated
        case userSignedUp
        case userSignedIn
        case userSignedOut
        case passwordResetRequested
        case accountDeleted
        case profileUpdated
        case emailVerificationSent
        case exportCompleted
        case barcodeScanned
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
                self?.preloadInterstitialAd()
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

        completionCount += 1
        if shouldShowAdNow() {
            currentAdType = determineAdType(for: event)
            loadAndShowAd()
        }
        #endif
    }

    private func shouldShowAdNow() -> Bool {
        guard completionCount >= actionsBeforeAd else { return false }
        return Date().timeIntervalSince(lastAdShown) >= minTimeBetweenAds
    }

    private func determineAdType(for event: CompletionEvent) -> AdType {
        switch event {
        case .inventoryCountCompleted, .exportCompleted:
            return .interstitial
        case .storageCreated, .itemAdded, .userSignedUp, .barcodeScanned:
            return .interstitial
        case .settingsChanged, .itemUpdated, .storageUpdated,
             .userSignedIn, .userSignedOut, .passwordResetRequested,
             .accountDeleted, .profileUpdated, .emailVerificationSent:
            return .banner
        }
    }

    // MARK: - Ad Loading & Display

    private func loadAndShowAd() {
        switch currentAdType {
        case .interstitial, .reward:
            // Reward ads use interstitial as fallback until premium features land
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
        let unitID = isLiveBuild ? interstitialAdUnitID : testInterstitialUnitID
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: unitID, request: request) { [weak self] ad, error in
            let wrapped = ad.map { SendableAd(value: $0) }
            let errorMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorMsg {
                    print("AdMob: Interstitial preload failed — \(errorMsg)")
                    return
                }
                self.interstitialAd = wrapped?.value
                self.interstitialAd?.fullScreenContentDelegate = self
                print("AdMob: Interstitial preloaded and ready.")
            }
        }
        #endif
    }

    private func loadInterstitialAd() {
        #if !targetEnvironment(simulator)
        isAdLoading = true
        adLoadError = nil

        let unitID = isLiveBuild ? interstitialAdUnitID : testInterstitialUnitID
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: unitID, request: request) { [weak self] ad, error in
            let wrapped = ad.map { SendableAd(value: $0) }
            let errorMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAdLoading = false
                if let errorMsg {
                    self.adLoadError = errorMsg
                    print("AdMob: Interstitial load failed — \(errorMsg)")
                    return
                }
                self.interstitialAd = wrapped?.value
                self.interstitialAd?.fullScreenContentDelegate = self
                self.shouldShowAd = true
                self.lastAdShown = Date()
                self.completionCount = 0
            }
        }
        #endif
    }

    private func loadRewardAd() {
        #if !targetEnvironment(simulator)
        isAdLoading = true
        adLoadError = nil

        let unitID = isLiveBuild ? rewardAdUnitID : testRewardUnitID
        let request = GADRequest()
        GADRewardedAd.load(withAdUnitID: unitID, request: request) { [weak self] ad, error in
            let wrapped = ad.map { SendableAd(value: $0) }
            let errorMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAdLoading = false
                if let errorMsg {
                    self.adLoadError = errorMsg
                    print("AdMob: Reward ad load failed — \(errorMsg)")
                    return
                }
                self.rewardAd = wrapped?.value
                self.rewardAd?.fullScreenContentDelegate = self
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
        guard let ad = interstitialAd else {
            print("AdMob: Interstitial not ready — preloading for next opportunity.")
            preloadInterstitialAd()
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        ad.present(fromRootViewController: root)
        #endif
    }

    func showRewardAd(completion: @escaping (Bool) -> Void) {
        #if !targetEnvironment(simulator)
        guard let ad = rewardAd else {
            print("AdMob: Reward ad not ready.")
            completion(false)
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            completion(false)
            return
        }
        ad.present(fromRootViewController: root) {
            completion(true)
        }
        #else
        completion(false)
        #endif
    }

    // MARK: - Reward Ad for Premium Preview

    /// Show a reward ad that unlocks a premium feature for 24 hours.
    func showRewardForPremiumPreview(feature: String, completion: @escaping (Bool) -> Void) {
        #if !targetEnvironment(simulator)
        if rewardAd != nil {
            showRewardAd(completion: completion)
        } else {
            loadRewardAd()
            // Notify caller it's loading
            completion(false)
        }
        #else
        // In simulator, simulate a successful reward
        completion(true)
        #endif
    }

    // MARK: - Controls

    func dismissAd() {
        shouldShowAd = false
        // Pre-load next interstitial so it's ready
        preloadInterstitialAd()
    }

    func disableAds() {
        completionCount = 0
        shouldShowAd = false
        isAdLoading = false
        adLoadError = nil
    }

    // MARK: - Debug / Testing

    func showTestAd(type: AdType = .interstitial) {
        currentAdType = type
        switch type {
        case .interstitial, .reward:
            loadInterstitialAd()
        case .banner:
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
}

// MARK: - GADFullScreenContentDelegate

#if !targetEnvironment(simulator)
@MainActor
extension AdManager: @preconcurrency GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        shouldShowAd = false
        preloadInterstitialAd()
        print("AdMob: Ad dismissed — preloading next.")
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        shouldShowAd = false
        adLoadError = error.localizedDescription
        print("AdMob: Ad failed to present — \(error.localizedDescription)")
    }

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("AdMob: Ad presenting full screen.")
    }
}
#endif

// MARK: - Banner Ad View

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    #if !targetEnvironment(simulator)
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        // Use the key window's root view controller (non-deprecated approach)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            banner.rootViewController = root
        }
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}

    #else
    func makeUIView(context: Context) -> UIView {
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
                }

                Button(action: onDismiss) {
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
        }
    }
}

// MARK: - Reward Ad Trigger View

struct RewardAdTrigger: View {
    @ObservedObject var adManager: AdManager
    let featureName: String
    let onDismiss: () -> Void
    let onRewardClaimed: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gift.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("Unlock \(featureName)")
                .font(.title2)
                .fontWeight(.bold)

            Text("Watch a short ad to unlock this feature for 24 hours.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if adManager.isAdLoading {
                ProgressView("Loading ad...")
            } else {
                Button {
                    adManager.showRewardAd { success in
                        if success { onRewardClaimed() }
                        onDismiss()
                    }
                } label: {
                    Label("Watch Ad", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }

            Button("No thanks", action: onDismiss)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Ad Integration Container

/// Wrap your main content in this view to automatically handle
/// banner and interstitial ads based on user actions.
struct RealAdIntegrationView<Content: View>: View {
    @StateObject private var adManager = AdManager.shared
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content

            // Persistent banner ad — shown above the tab bar when triggered
            if adManager.shouldShowAd && adManager.currentAdType == .banner {
                VStack {
                    Spacer()
                    BannerAdView(adUnitID: adManager.bannerAdUnitID)
                        .frame(height: 50)
                        .padding(.bottom, 90) // clear the custom tab bar
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: adManager.shouldShowAd)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { adManager.shouldShowAd && adManager.currentAdType == .interstitial },
                set: { _ in }
            )
        ) {
            InterstitialAdTrigger(adManager: adManager) {
                adManager.dismissAd()
            }
        }
    }
}
