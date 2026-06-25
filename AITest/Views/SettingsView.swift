import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject private var firestoreManager: FirestoreManager
    @Query private var items: [InventoryItem]
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var teamManager = TeamManager.shared
    @StateObject private var adManager = AdManager.shared
    @StateObject private var trackingManager = TrackingPermissionManager.shared

    @AppStorage(NotificationManager.dailySummaryEnabledKey) private var dailySummaryEnabled = false
    @AppStorage(NotificationManager.dailySummaryHourKey) private var dailySummaryHour = 18
    @AppStorage(NotificationManager.dailySummaryMinuteKey) private var dailySummaryMinute = 0
    @State private var dailySummaryTime = Calendar.current.date(
        from: DateComponents(hour: 18, minute: 0)
    ) ?? Date()

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
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
                                Text("Stoqly Pro")
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
                        .foregroundColor(.stoqlyPrimary)
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
                        .foregroundColor(.stoqlyPrimary)
                    }
                } header: {
                    Text("Subscription")
                }

                if subscriptionManager.isPro {
                    Section(header: Text("Team")) {
                        NavigationLink(destination: TeamMembersView()) {
                            Label("Team Members", systemImage: "person.2.fill")
                        }
                    }

                    Section(header: Text("Inventory")) {
                        NavigationLink(destination: TemplatesListView()) {
                            Label("Item Templates", systemImage: "doc.on.doc.fill")
                        }
                        .accessibilityIdentifier("itemTemplatesRow")

                        NavigationLink(destination: BulkImportView()) {
                            Label("Import Items (CSV / Excel)", systemImage: "square.and.arrow.down.on.square")
                        }
                        .accessibilityIdentifier("bulkImportRow")
                    }
                }

                if teamManager.isInTeamWorkspace {
                    Section {
                        Button(role: .destructive) {
                            teamManager.leaveWorkspace()
                            Task {
                                await firestoreManager.pullFromCloud(modelContext: modelContext)
                            }
                        } label: {
                            Label("Leave Team Workspace", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section(header: Text("Daily Summary")) {
                    Toggle("End-of-day stock summary", isOn: $dailySummaryEnabled)
                        .onChange(of: dailySummaryEnabled) { _, enabled in
                            if enabled {
                                rescheduleDailySummary()
                            } else {
                                NotificationManager.shared.cancelDailySummary()
                            }
                        }
                    if dailySummaryEnabled {
                        DatePicker(
                            "Notify at",
                            selection: $dailySummaryTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: dailySummaryTime) { _, newTime in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                            dailySummaryHour = parts.hour ?? 18
                            dailySummaryMinute = parts.minute ?? 0
                            rescheduleDailySummary()
                        }
                    }
                }

                // MARK: - Currency
                Section(header: Text("Currency")) {
                    Picker("Currency", selection: $currencyManager.selectedCurrency) {
                        ForEach(Currency.currencies, id: \.code) { currency in
                            CurrencyRow(currency: currency)
                                .tag(currency)
                                .accessibilityIdentifier("currency_\(currency.code)")
                        }
                    }
                    .pickerStyle(NavigationLinkPickerStyle())
                    .accessibilityIdentifier("settingsCurrencyPicker")
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
                        .foregroundColor(.stoqlyPrimary)
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
                                .foregroundColor(.stoqlyPrimary)
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

                // MARK: - AI Features
                Section(header: Text("AI Features")) {
                    AIAPIKeyRow()
                }

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
                        Text("Stoqly")
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
            PaywallView(source: "pro_feature")
                .sheetStyle()
        }
        .task {
            await subscriptionManager.loadProducts()
        }
        .onAppear {
            dailySummaryTime = Calendar.current.date(
                from: DateComponents(hour: dailySummaryHour, minute: dailySummaryMinute)
            ) ?? dailySummaryTime
            if dailySummaryEnabled {
                rescheduleDailySummary()
            }
        }
    }

    private func rescheduleDailySummary() {
        let lowStockCount = items.filter { $0.isLowStock || $0.isOutOfStock }.count
        let expiringCount = items.filter { $0.isExpiringSoon || $0.isExpired }.count
        NotificationManager.shared.scheduleDailySummary(
            hour: dailySummaryHour,
            minute: dailySummaryMinute,
            lowStockCount: lowStockCount,
            expiringCount: expiringCount
        )
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

// MARK: - AIAPIKeyRow
//
// Lets the user paste their Anthropic API key directly from Settings.
// The key is stored in UserDefaults (not Keychain for simplicity at this stage).
// If Secrets.plist is present it takes precedence; otherwise UserDefaults is used.

struct AIAPIKeyRow: View {
    @AppStorage("stoqly_anthropic_api_key") private var savedKey: String = ""
    @State private var editingKey = ""
    @State private var isEditing = false
    @State private var showKey = false

    private var effectiveKey: String {
        SecretsManager.anthropicAPIKey ?? savedKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Anthropic API Key", systemImage: "sparkles")
                Spacer()
                if !effectiveKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.stoqlySuccess)
                        .font(.caption)
                }
            }

            if isEditing {
                HStack {
                    if showKey {
                        TextField("sk-ant-api03-…", text: $editingKey)
                            .font(.caption)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("sk-ant-api03-…", text: $editingKey)
                            .font(.caption)
                    }
                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.stoqlyCard)
                .cornerRadius(8)

                HStack {
                    Button("Save") {
                        savedKey = editingKey.trimmingCharacters(in: .whitespaces)
                        isEditing = false
                    }
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.stoqlyPrimary)

                    Spacer()

                    Button("Cancel") {
                        isEditing = false
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                if effectiveKey.isEmpty {
                    Button("Add API Key") {
                        editingKey = savedKey
                        isEditing = true
                    }
                    .font(.caption)
                    .foregroundColor(.stoqlyPrimary)
                    Text("Required for Voice, Photo, and Sheet inventory features.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text(SecretsManager.anthropicAPIKey != nil ? "Configured via Secrets.plist" : "•••••••••••••••••••••")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if SecretsManager.anthropicAPIKey == nil {
                            Button("Change") {
                                editingKey = savedKey
                                isEditing = true
                            }
                            .font(.caption)
                            .foregroundColor(.stoqlyPrimary)
                        }
                    }
                }
            }
        }
    }
}

extension SecretsManager {
    /// Returns the API key from Secrets.plist OR UserDefaults (Settings input).
    static var effectiveAnthropicKey: String? {
        if let key = anthropicAPIKey, !key.isEmpty { return key }
        let stored = UserDefaults.standard.string(forKey: "stoqly_anthropic_api_key") ?? ""
        return stored.isEmpty ? nil : stored
    }
}

#Preview {
    SettingsView()
        .environmentObject(CurrencyManager())
}
