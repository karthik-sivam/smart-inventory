import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var adManager = AdManager.shared
    @StateObject private var trackingManager = TrackingPermissionManager.shared

    @State private var showPaywall = false

    var body: some View {
        NavigationView {
            Form {

                // MARK: - Subscription Status
                Section {
                    if subscriptionManager.isPro {
                        // Pro user — show status
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "star.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Inventory Pro")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text("Unlimited storages · Advanced analytics · No ads")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)

                        Button("Manage Subscription") {
                            if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.blue)
                    } else {
                        // Free user — upgrade prompt
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "star")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free Plan")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text("Up to 5 storages, 50 items per storage · Upgrade for unlimited")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("Upgrade to Pro", systemImage: "arrow.up.circle.fill")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(subscriptionManager.formattedPrice(for: .proMonthly) + "/mo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                .cornerRadius(10)
                                .padding(.horizontal, 2)
                        )

                        Button("Restore Purchases") {
                            Task { await subscriptionManager.restorePurchases() }
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                } header: {
                    Text("Subscription")
                }

                // MARK: - Currency
                Section(header: Text("Currency")) {
                    Picker("Currency", selection: $currencyManager.selectedCurrency) {
                        ForEach(Currency.currencies, id: \.code) { currency in
                            CurrencyRow(currency: currency)
                                .tag(currency)
                        }
                    }
                    .pickerStyle(NavigationLinkPickerStyle())
                    .onChange(of: currencyManager.selectedCurrency) { _, _ in
                        AdManager.shared.recordCompletion(event: .settingsChanged)
                    }
                }

                // MARK: - Privacy & Ads
                Section(header: Text("Privacy & Ads")) {
                    HStack {
                        Label("Ad Tracking", systemImage: "eye.slash")
                        Spacer()
                        Text(trackingManager.statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if subscriptionManager.shouldShowAds {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Label("Ad Tracking Settings", systemImage: "hand.raised")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }

                // MARK: - DEBUG: Advertisement Testing
                #if DEBUG
                Section(header: Text("Debug — Ads")) {
                    // AdMob initialization status
                    HStack {
                        Label("AdMob SDK", systemImage: adManager.isInitialized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(adManager.isInitialized ? .green : .red)
                        Spacer()
                        Text(adManager.isInitialized ? "Initialized" : "Not initialized")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // ATT status
                    HStack {
                        Label("ATT Permission", systemImage: "person.badge.shield.checkmark.fill")
                        Spacer()
                        Text(trackingManager.statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        AdManager.shared.showTestAd(type: .interstitial)
                    } label: {
                        Label("Test Interstitial Ad", systemImage: "rectangle.stack")
                    }

                    Button {
                        AdManager.shared.showTestAd(type: .banner)
                    } label: {
                        Label("Test Banner Ad", systemImage: "rectangle.bottomthird.inset.filled")
                    }

                    Button {
                        AdManager.shared.showTestAd(type: .reward)
                    } label: {
                        Label("Test Reward Ad", systemImage: "gift")
                    }

                    // Test device IDs
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test Devices (\(AdManager.shared.getTestDeviceIDs().count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text("Check Xcode console for your device ID when first loading ads. Paste it into AdManager.swift.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(AdManager.shared.getTestDeviceIDs(), id: \.self) { id in
                            Text(id)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Debug — Subscription")) {
                    HStack {
                        Label("Pro Status", systemImage: "star.circle")
                        Spacer()
                        Text(subscriptionManager.isPro ? "Pro ✓" : "Free")
                            .font(.caption)
                            .foregroundColor(subscriptionManager.isPro ? .green : .secondary)
                    }
                    HStack {
                        Label("Ads Removed", systemImage: "xmark.circle")
                        Spacer()
                        Text(subscriptionManager.hasRemovedAds ? "Yes" : "No")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Open Paywall", systemImage: "creditcard")
                    }
                    Button {
                        Task { await subscriptionManager.loadProducts() }
                    } label: {
                        Label("Reload Products", systemImage: "arrow.clockwise")
                    }
                }
                #endif

                // MARK: - About
                Section(header: Text("About")) {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("App", systemImage: "cube.box")
                        Spacer()
                        Text("Smart Inventory")
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Account
                Section(header: Text("Account")) {
                    Button {
                        AuthManager.shared.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task {
            await subscriptionManager.loadProducts()
        }
    }
}

struct CurrencyRow: View {
    let currency: Currency

    var body: some View {
        HStack {
            Text(currency.symbol)
                .frame(width: 30, alignment: .leading)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(currency.name)
                    .font(.headline)
                Text(currency.code)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CurrencyManager())
}
