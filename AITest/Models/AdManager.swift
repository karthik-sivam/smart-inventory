import Foundation
import SwiftUI

class AdManager: ObservableObject {
    @Published var shouldShowAd = false
    @Published var currentAdType: AdType = .interstitial
    
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
    }
    
    static let shared = AdManager()
    
    private init() {}
    
    func recordCompletion(event: CompletionEvent) {
        completionCount += 1
        
        if shouldShowAdNow() {
            currentAdType = determineAdType(for: event)
            showAd()
        }
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
            return .reward
        case .storageCreated, .itemAdded:
            return .interstitial
        case .settingsChanged, .itemUpdated, .storageUpdated:
            return .banner
        }
    }
    
    private func showAd() {
        shouldShowAd = true
        lastAdShown = Date()
        completionCount = 0
    }
    
    func dismissAd() {
        shouldShowAd = false
    }
    
    func showTestAd(type: AdType = .interstitial) {
        currentAdType = type
        showAd()
    }
    
    func disableAds() {
        completionCount = 0
        shouldShowAd = false
    }
}

// MARK: - Ad View Components

struct InterstitialAdView: View {
    @ObservedObject var adManager: AdManager
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 250)
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                            
                            Text("Upgrade to Premium")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Remove ads and unlock advanced features")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                onDismiss()
                            }) {
                                Text("Upgrade Now")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(25)
                            }
                        }
                        .padding()
                    )
                
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Continue")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(20)
                }
            }
            .padding()
        }
    }
}

struct BannerAdView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "star.circle.fill")
                .foregroundColor(.yellow)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Inventory Pro")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Advanced analytics & reporting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Upgrade") {
                onDismiss()
            }
            .font(.caption)
            .foregroundColor(.blue)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct RewardAdView: View {
    @ObservedObject var adManager: AdManager
    let onDismiss: () -> Void
    let onRewardClaimed: () -> Void
    
    @State private var countdown = 5
    @State private var showReward = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if showReward {
                    // Reward claimed view
                    VStack(spacing: 16) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Reward Unlocked!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Premium feature unlocked for 24 hours")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Claim Reward") {
                            onRewardClaimed()
                            onDismiss()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(25)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                } else {
                    // Ad viewing phase
                    VStack(spacing: 16) {
                        Text("Watch ad to unlock premium features")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        // Mock video ad placeholder
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray)
                            .frame(height: 200)
                            .overlay(
                                VStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.white)
                                    
                                    Text("Ad playing...")
                                        .foregroundColor(.white)
                                    
                                    Text("\(countdown)s")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                            )
                        
                        Button("Skip") {
                            onDismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(16)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            startCountdown()
        }
    }
    
    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            countdown -= 1
            if countdown <= 0 {
                timer.invalidate()
                showReward = true
            }
        }
    }
}

// MARK: - Ad Integration Helper

struct AdIntegrationView: View {
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
                    BannerAdView {
                        adManager.dismissAd()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100) // Above tab bar
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { adManager.shouldShowAd && adManager.currentAdType == .interstitial },
            set: { _ in }
        )) {
            InterstitialAdView(adManager: adManager) {
                adManager.dismissAd()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { adManager.shouldShowAd && adManager.currentAdType == .reward },
            set: { _ in }
        )) {
            RewardAdView(adManager: adManager, onDismiss: {
                adManager.dismissAd()
            }, onRewardClaimed: {
                // Handle reward logic here
                print("Reward claimed!")
            })
        }
    }
} 