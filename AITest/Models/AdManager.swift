import Foundation
import SwiftUI
#if !targetEnvironment(simulator)
import GoogleMobileAds
#endif

// MARK: - Premium Features Documentation
/*
 TODO: PREMIUM FEATURES - To be implemented in future versions
 
 Planned Premium Features:
 1. Advanced Analytics & Reports
    - Detailed inventory reports
    - Trend analysis
    - Export functionality (PDF, CSV)
    - Custom date range reports
 
 2. Multi-User Collaboration
    - Team management
    - Role-based permissions
    - Activity logs
    - Shared inventory access
 
 3. Advanced Notifications
    - Custom alert thresholds
    - Push notifications
    - Email alerts
    - SMS notifications
 
 4. Cloud Sync & Backup
    - Unlimited cloud storage
    - Automatic backups
    - Cross-device sync
    - Data recovery
 
 5. Barcode Scanner Pro
    - Bulk scanning
    - Custom barcode formats
    - Offline scanning
    - History tracking
 
 6. Advanced Search & Filtering
    - Saved searches
    - Advanced filters
    - Search history
    - Smart suggestions
 
 7. Custom Branding
    - Custom app themes
    - Company logo integration
    - Custom reports branding
    - White-label options
 
 8. API Integration
    - Third-party integrations
    - Webhook support
    - Custom API endpoints
    - Data import/export
 
 Reward Ads will unlock temporary access to these premium features.
 Subscription model will provide permanent access.
 */

class AdManager: NSObject, ObservableObject {
    @Published var shouldShowAd = false
    @Published var currentAdType: AdType = .interstitial
    @Published var isAdLoading = false
    @Published var adLoadError: String?
    
    // Ad Unit IDs - Replace with your actual AdMob ad unit IDs
    let bannerAdUnitID = "ca-app-pub-9489340523484530/3501995184"
    let interstitialAdUnitID = "ca-app-pub-9489340523484530/1789458261"
    let rewardAdUnitID = "ca-app-pub-9489340523484530/3557835507" // Test reward
    
    #if targetEnvironment(simulator)
    // Simulator: No ad objects
    private var interstitialAd: Any?
    private var rewardAd: Any?
    #else
    // Real device: Ad objects
    private var interstitialAd: GADInterstitialAd?
    private var rewardAd: GADRewardedAd?
    #endif
    
    private var completionCount = 0
    private var lastAdShown = Date.distantPast
    private let minTimeBetweenAds: TimeInterval = 300 // 5 minutes
    private let actionsBeforeAd = 3 // Show ad every 3 completed actions
    
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
    }
    
    static let shared = AdManager()
    
    private override init() {
        super.init()
        initializeAdMob()
    }
    
    private func initializeAdMob() {
        #if targetEnvironment(simulator)
        print("AdMob disabled in simulator")
        return
        #else
        // Check if we have a valid app ID
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
              !appID.isEmpty else {
            print("AdMob disabled - no valid app ID found")
            return
        }
        
        // Initialize AdMob
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        print("AdMob initialized successfully with app ID: \(appID)")
        #endif
    }
    
    func recordCompletion(event: CompletionEvent) {
        #if targetEnvironment(simulator)
        // Skip ad tracking in simulator
        return
        #else
        completionCount += 1
        
        if shouldShowAdNow() {
            currentAdType = determineAdType(for: event)
            loadAndShowAd()
        }
        #endif
    }
    
    private func shouldShowAdNow() -> Bool {
        let timeSinceLastAd = Date().timeIntervalSince(lastAdShown)
        if timeSinceLastAd < minTimeBetweenAds {
            return false
        }
        return completionCount >= actionsBeforeAd
    }
    
    private func determineAdType(for event: CompletionEvent) -> AdType {
        switch event {
        case .inventoryCountCompleted:
            // TODO: PREMIUM FEATURE - Reward ads for premium features
            // Temporarily disabled until premium features are ready
            // return .reward
            return .interstitial
        case .storageCreated, .itemAdded, .userSignedUp, .userSignedIn:
            return .interstitial
        case .settingsChanged, .itemUpdated, .storageUpdated, .userSignedOut, .passwordResetRequested, .accountDeleted, .profileUpdated, .emailVerificationSent:
            return .banner
        }
    }
    
    private func loadAndShowAd() {
        switch currentAdType {
        case .interstitial:
            loadInterstitialAd()
        case .reward:
            // TODO: PREMIUM FEATURE - Reward ads for premium features
            // Temporarily disabled until premium features are ready
            // loadRewardAd()
            loadInterstitialAd() // Fallback to interstitial
        case .banner:
            // Banner ads are loaded automatically by the view
            shouldShowAd = true
            lastAdShown = Date()
            completionCount = 0
        }
    }
    
    private func loadInterstitialAd() {
        #if targetEnvironment(simulator)
        print("Interstitial ad loading disabled in simulator")
        shouldShowAd = false
        return
        #else
        isAdLoading = true
        adLoadError = nil
        
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isAdLoading = false
                
                if let error = error {
                    self?.adLoadError = error.localizedDescription
                    print("Interstitial ad failed to load: \(error.localizedDescription)")
                    return
                }
                
                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self
                self?.shouldShowAd = true
                self?.lastAdShown = Date()
                self?.completionCount = 0
            }
        }
        #endif
    }
    
    private func loadRewardAd() {
        #if targetEnvironment(simulator)
        print("Reward ad loading disabled in simulator")
        shouldShowAd = false
        return
        #else
        isAdLoading = true
        adLoadError = nil
        
        let request = GADRequest()
        GADRewardedAd.load(withAdUnitID: rewardAdUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isAdLoading = false
                
                if let error = error {
                    self?.adLoadError = error.localizedDescription
                    print("Reward ad failed to load: \(error.localizedDescription)")
                    return
                }
                
                self?.rewardAd = ad
                self?.rewardAd?.fullScreenContentDelegate = self
                self?.shouldShowAd = true
                self?.lastAdShown = Date()
                self?.completionCount = 0
            }
        }
        #endif
    }
    
    func showInterstitialAd() {
        #if targetEnvironment(simulator)
        print("Interstitial ad showing disabled in simulator")
        return
        #else
        guard let interstitialAd = interstitialAd else {
            print("Interstitial ad not ready")
            return
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            interstitialAd.present(fromRootViewController: rootViewController)
        }
        #endif
    }
    
    func showRewardAd(completion: @escaping (Bool) -> Void) {
        #if targetEnvironment(simulator)
        print("Reward ad showing disabled in simulator")
        completion(false)
        return
        #else
        guard let rewardAd = rewardAd else {
            print("Reward ad not ready")
            completion(false)
            return
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rewardAd.present(fromRootViewController: rootViewController) {
                // User earned reward
                completion(true)
            }
        } else {
            completion(false)
        }
        #endif
    }
    
    func dismissAd() {
        shouldShowAd = false
    }
    
    func showTestAd(type: AdType = .interstitial) {
        currentAdType = type
        loadAndShowAd()
    }
    
    func disableAds() {
        completionCount = 0
        shouldShowAd = false
        isAdLoading = false
        adLoadError = nil
    }
}

#if !targetEnvironment(simulator)
// MARK: - GADFullScreenContentDelegate
extension AdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        shouldShowAd = false
        print("Ad dismissed")
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        shouldShowAd = false
        adLoadError = error.localizedDescription
        print("Ad failed to present: \(error.localizedDescription)")
    }
}
#endif

// MARK: - Real Ad View Components

#if !targetEnvironment(simulator)
struct RealBannerAdView: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView(adSize: GADAdSizeBanner)
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = UIApplication.shared.windows.first?.rootViewController
        bannerView.load(GADRequest())
        return bannerView
    }
    
    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // No updates needed
    }
}
#else
struct RealBannerAdView: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> UIView {
        let placeholderView = UIView()
        placeholderView.backgroundColor = UIColor.systemGray5
        return placeholderView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed
    }
}
#endif

struct InterstitialAdTrigger: View {
    @ObservedObject var adManager: AdManager
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            if adManager.isAdLoading {
                ProgressView("Loading ad...")
                    .padding()
            } else if let error = adManager.adLoadError {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text("Ad failed to load")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Continue") {
                        onDismiss()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            } else {
                Button("Show Ad") {
                    adManager.showInterstitialAd()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .onAppear {
            if adManager.shouldShowAd && adManager.currentAdType == .interstitial {
                adManager.showInterstitialAd()
            }
        }
    }
}

// TODO: PREMIUM FEATURE - Reward ads for premium features
// Temporarily disabled until premium features are ready
struct RewardAdTrigger: View {
    @ObservedObject var adManager: AdManager
    let onDismiss: () -> Void
    let onRewardClaimed: () -> Void
    
    var body: some View {
        VStack {
            if adManager.isAdLoading {
                ProgressView("Loading reward ad...")
                    .padding()
            } else if let error = adManager.adLoadError {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text("Reward ad failed to load")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Continue") {
                        onDismiss()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            } else {
                Button("Watch Ad for Reward") {
                    adManager.showRewardAd { success in
                        if success {
                            onRewardClaimed()
                        }
                        onDismiss()
                    }
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .onAppear {
            if adManager.shouldShowAd && adManager.currentAdType == .reward {
                adManager.showRewardAd { success in
                    if success {
                        onRewardClaimed()
                    }
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Ad Integration Helper

struct RealAdIntegrationView: View {
    @StateObject private var adManager = AdManager.shared
    let content: AnyView
    
    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }
    
    var body: some View {
        ZStack {
            content
            
            // Banner ad overlay
            if adManager.shouldShowAd && adManager.currentAdType == .banner {
                VStack {
                    Spacer()
                    RealBannerAdView(adUnitID: adManager.bannerAdUnitID)
                        .frame(height: 50)
                        .padding(.horizontal)
                        .padding(.bottom, 100) // Above tab bar
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { adManager.shouldShowAd && adManager.currentAdType == .interstitial },
            set: { _ in }
        )) {
            InterstitialAdTrigger(adManager: adManager) {
                adManager.dismissAd()
            }
        }
        // TODO: PREMIUM FEATURE - Reward ads for premium features
        // Temporarily disabled until premium features are ready
        /*
        .fullScreenCover(isPresented: Binding(
            get: { adManager.shouldShowAd && adManager.currentAdType == .reward },
            set: { _ in }
        )) {
            RewardAdTrigger(adManager: adManager, onDismiss: {
                adManager.dismissAd()
            }, onRewardClaimed: {
                // Handle reward logic here
                print("Reward claimed!")
            })
        }
        */
    }
} 
