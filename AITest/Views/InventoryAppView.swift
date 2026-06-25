import SwiftUI
import SwiftData
import UIKit

struct InventoryAppView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var firestoreManager: FirestoreManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var trackingManager: TrackingPermissionManager
    @Environment(\.modelContext) private var modelContext

    @Query private var storages: [Storage]
    @Query private var items: [InventoryItem]

    @State private var selectedTab = 0
    @StateObject private var currencyManager = CurrencyManager()

    // Onboarding: shown once on first ever launch (Maestro: launchApp arguments UITestResetOnboarding: true)
    @State private var showOnboarding = !UserDefaults.hasCompletedOnboarding

    // Post-login guided onboarding (shown once after first sign-in when storages.isEmpty).
    @State private var showPostLoginOnboarding = false
    private static let postLoginOnboardingKey = "postLoginOnboardingShown"

    // Paywall
    @State private var showPaywall = false

    // Prevents running startup sync more than once per in-memory session.
    // Deliberately NOT persisted — after reinstall we always want a fresh pull.
    @State private var hasSyncedThisSession = false

    /// One-time Core Spotlight bulk index after the first non-empty items fetch.
    @AppStorage("spotlightIndexedOnce") private var spotlightIndexedOnce = false

    @State private var pendingInvites: [TeamManager.PendingInvite] = []
    @State private var showingInviteAlert = false

    /// Maestro passes `UITestResetOnboarding: true` via launchApp arguments (see maestro/flows/01_onboarding.yaml).
    private static func shouldForceOnboardingForMaestroUITest() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestResetOnboarding") { return true }
        return args.contains { $0.contains("UITestResetOnboarding") }
    }

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                RealAdIntegrationView {
                    MainAppContent(
                        selectedTab: $selectedTab,
                        currencyManager: currencyManager,
                        showPaywall: $showPaywall
                    )
                    .environmentObject(subscriptionManager)
                    .environmentObject(firestoreManager)
                }
            } else {
                AuthView()
            }
        }
        // Onboarding sheet — shown before auth on first launch
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        // Post-login onboarding — shown once after first sign-in when storages.isEmpty
        .fullScreenCover(isPresented: $showPostLoginOnboarding) {
            PostLoginOnboardingView(isPresented: $showPostLoginOnboarding)
        }
        // Paywall sheet
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "unknown")
                .sheetStyle()
        }
        .task {
            // Ask ATT first, then prompt for notifications.
            await trackingManager.requestPermissionIfNeeded()
            NotificationManager.shared.requestPermission()
        }
        // Triggered whenever auth state changes (sign in / sign out)
        .onChange(of: authManager.isAuthenticated) { _, isAuthed in
            if isAuthed {
                // `selectedTab` survives across the auth gate; signing out from Profile left tab 4,
                // which hid the dashboard until the user tapped Dashboard manually (Maestro: 04_signin).
                selectedTab = 0
                runStartupSync()
                maybeShowPostLoginOnboarding()
                Task { await checkPendingInvites() }
            } else {
                // User signed out — clear all local data immediately.
                // This prevents data from leaking to the next signed-in user.
                clearLocalData()
                // Reset sync flag so the next sign-in triggers a fresh cloud pull.
                hasSyncedThisSession = false
                spotlightIndexedOnce = false
                TeamManager.shared.reset()
            }
        }
        .alert("Team Invitation", isPresented: $showingInviteAlert,
               presenting: pendingInvites.first) { invite in
            Button("Join as \(invite.role.capitalized)") {
                Task {
                    await TeamManager.shared.acceptInvite(invite, modelContext: modelContext)
                    pendingInvites = []
                    showingInviteAlert = false
                    await firestoreManager.pullFromCloud(modelContext: modelContext)
                }
            }
            Button("Decline", role: .destructive) {
                Task {
                    await TeamManager.shared.declineInvite(invite)
                    pendingInvites = []
                    showingInviteAlert = false
                }
            }
        } message: { invite in
            Text("\(invite.ownerName) has invited you to their Stoqly workspace as \(invite.role).")
        }
        .onChange(of: items.count) { _, _ in
            guard !spotlightIndexedOnce, !items.isEmpty else { return }
            SpotlightManager.shared.reindexAll(Array(items))
            spotlightIndexedOnce = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            NotificationManager.shared.checkAndNotifyLowStock(items: items)
            Task {
                await subscriptionManager.refreshPurchaseStatus()
                let throttleInterval: TimeInterval = 15 * 60
                let lastSync = firestoreManager.lastSyncDate ?? .distantPast
                if Date().timeIntervalSince(lastSync) > throttleInterval {
                    await firestoreManager.pullFromCloud(modelContext: modelContext)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)) { _ in
            let capturedItems = items
            let capturedStorages = storages
            Task {
                var bgTask = UIBackgroundTaskIdentifier.invalid
                bgTask = UIApplication.shared.beginBackgroundTask(withName: "stoqly.syncFlush") {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
                await FirestoreManager.shared.flushPending(
                    storages: capturedStorages,
                    items: capturedItems
                )
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        // Also run on appear in case the user was already signed in
        // when the app launched (persisted session)
        .onAppear {
            if Self.shouldForceOnboardingForMaestroUITest() {
                showOnboarding = true
            }
            if authManager.isAuthenticated {
                runStartupSync()
                maybeShowPostLoginOnboarding()
                Task { await checkPendingInvites() }
            }
        }
        .saveErrorBanner()
    }

    private func checkPendingInvites() async {
        let invites = await TeamManager.shared.checkPendingInvites()
        if !invites.isEmpty {
            pendingInvites = invites
            showingInviteAlert = true
        }
    }

    // MARK: - Post-login onboarding

    /// Trigger the post-login guided flow only on the user's very first signed-in
    /// session with no storages. After it runs once we persist the flag so it
    /// never reappears, even if the user later deletes all their storages.
    /// Skipped automatically when storages already exist (covers re-installs
    /// where the cloud pull restores data) or when Maestro is force-resetting
    /// onboarding (the pre-auth onboarding will already be visible).
    private func maybeShowPostLoginOnboarding() {
        guard !Self.shouldForceOnboardingForMaestroUITest() else { return }
        let alreadyShown = UserDefaults.standard.bool(forKey: Self.postLoginOnboardingKey)
        // Storages may still be empty for a brief moment after sign-in while the
        // cloud pull is in flight, so we re-check after a short delay rather than
        // racing the pull. If the pull restores data the second check sees
        // !isEmpty and the flow stays dismissed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !alreadyShown,
                  authManager.isAuthenticated,
                  storages.isEmpty,
                  !showOnboarding else { return }
            UserDefaults.standard.set(true, forKey: Self.postLoginOnboardingKey)
            showPostLoginOnboarding = true
        }
    }

    // MARK: - Startup Sync Logic

    private func clearLocalData() {
        // Delete in dependency order: children before parents.
        // ActivityEvent and InventoryCount have no children.
        // InventoryItem depends on Storage and UOM.
        // Storage and UOM are roots for user-owned inventory data.
        do {
            try modelContext.delete(model: ActivityEvent.self)
            try modelContext.delete(model: InventoryCount.self)
            try modelContext.delete(model: InventoryBatch.self)
            try modelContext.delete(model: TeamMember.self)
            try modelContext.delete(model: ItemTemplate.self)
            try modelContext.delete(model: InventoryItem.self)
            try modelContext.delete(model: Storage.self)
            try modelContext.delete(model: UOM.self)
            modelContext.safeSave(context: "clearLocalData on sign-out")
            print("Local SwiftData cleared on sign-out.")
        } catch {
            print("clearLocalData failed: \(error.localizedDescription)")
        }
    }

    private func runStartupSync() {
        guard !hasSyncedThisSession else { return }
        hasSyncedThisSession = true

        Task {
            // Step 1 — Always pull from cloud first.
            //   • Normal login:   restores latest cloud data into local SwiftData.
            //   • After reinstall: SwiftData is empty, pull restores everything.
            //   • Brand-new user: cloud is empty, pull returns 0 — handled below.
            let cloudCount = await firestoreManager.pullFromCloud(modelContext: modelContext)

            // Step 2 — If cloud had nothing but local does, this is a first-time
            //           migration (user had data before cloud sync was introduced).
            //           Push local → cloud so nothing is lost.
            if cloudCount == 0 && !storages.isEmpty {
                print("Firestore: Cloud empty but local has \(storages.count) storages — migrating.")
                await firestoreManager.pushAllToCloud(storages: storages, items: items)
            }
        }
    }
}

// MARK: - Main App Content

struct MainAppContent: View {
    @Binding var selectedTab: Int
    @StateObject var currencyManager: CurrencyManager
    @Binding var showPaywall: Bool

    @EnvironmentObject private var firestoreManager: FirestoreManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack(alignment: .top) {
            // Native TabView — handles bottom safe area automatically so all tabs
            // scroll to their last item without anything hiding behind the bar.
            TabView(selection: $selectedTab) {
                DashboardView(selectedTab: $selectedTab)
                    .environmentObject(currencyManager)
                    .tabItem { Label("Dashboard", systemImage: "house.fill") }
                    .tag(0)

                StorageListView()
                    .environmentObject(currencyManager)
                    .tabItem { Label("Storages", systemImage: "archivebox.fill") }
                    .tag(1)

                ItemListView()
                    .environmentObject(currencyManager)
                    .tabItem { Label("Items", systemImage: "cube.box.fill") }
                    .tag(2)

                CountView()
                    .environmentObject(currencyManager)
                    .tabItem { Label("Audit", systemImage: "list.clipboard.fill") }
                    .tag(3)

                ProfileView()
                    .environmentObject(firestoreManager)
                    .environmentObject(subscriptionManager)
                    .tabItem { Label("Profile", systemImage: "person.circle.fill") }
                    .tag(4)
            }
            .tint(.stoqlyAccent)   // teal — matches the brand palette
        }
        .animation(.easeInOut(duration: 0.3), value: firestoreManager.syncState)
    }
}

// MARK: - Count View

struct CountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    @StateObject private var viewModel = CountViewModel()
    @State private var showingQuickCount: InventoryItem? = nil
    @State private var showingFullCount: InventoryItem? = nil
    @State private var pendingFullCountItem: InventoryItem? = nil
    @State private var lastCountedItem: InventoryItem? = nil
    @State private var showingSmartCount = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with progress
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audit")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(viewModel.countedThisSession.count) of \(viewModel.filteredItems.count) counted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                // Storage filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "All Storages",
                            isSelected: viewModel.selectedStorage == nil,
                            color: .stoqlyPrimary
                        ) {
                            viewModel.setSelectedStorage(nil)
                        }

                        ForEach(storages, id: \.id) { storage in
                            FilterChip(
                                title: storage.name,
                                isSelected: viewModel.selectedStorage?.id == storage.id,
                                color: Color(hex: storage.color) ?? .blue,
                                dot: true
                            ) {
                                viewModel.setSelectedStorage(storage)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Status filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "Due", isSelected: viewModel.statusFilter == .due, color: .stoqlyPrimary) {
                            viewModel.setStatusFilter(.due)
                        }
                        FilterChip(title: "Uncounted", isSelected: viewModel.statusFilter == .uncounted, color: .orange) {
                            viewModel.setStatusFilter(.uncounted)
                        }
                        FilterChip(title: "Low Stock", isSelected: viewModel.statusFilter == .lowStock, color: .red) {
                            viewModel.setStatusFilter(.lowStock)
                        }
                        FilterChip(title: "All", isSelected: viewModel.statusFilter == .all, color: .gray) {
                            viewModel.setStatusFilter(.all)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 6)

                // Search
                SearchBar(text: $viewModel.searchText, placeholder: "Search items to audit…")
                    .onChange(of: viewModel.searchText) { _, newValue in viewModel.setSearchText(newValue) }
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Item list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.filteredItems.isEmpty {
                            EmptyCountState()
                        } else {
                            ForEach(viewModel.filteredItems, id: \.id) { item in
                                if TeamManager.shared.canEdit {
                                    Button {
                                        lastCountedItem = item
                                        showingQuickCount = item
                                    } label: {
                                        CountItemCard(
                                            item: item,
                                            countedThisSession: viewModel.countedThisSession.contains(item.id)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityIdentifier("auditCountCard_\(item.sku.replacingOccurrences(of: "-", with: "_"))")
                                    .accessibilityLabel("Count \(item.name)")
                                } else {
                                    CountItemCard(
                                        item: item,
                                        countedThisSession: viewModel.countedThisSession.contains(item.id),
                                        showViewOnlyLock: true
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16) // native TabView handles bottom safe area
                }
                .padding(.top, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSmartCount = true
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(.stoqlyPrimary)
                    }
                    .accessibilityLabel("Smart Count")
                }
            }
        }
        .sheet(isPresented: $showingSmartCount) {
            SmartCountView().sheetStyle()
        }
        .sheet(item: $showingQuickCount, onDismiss: {
            if let item = lastCountedItem {
                viewModel.markCounted(item.id)
            }
            if let pending = pendingFullCountItem {
                pendingFullCountItem = nil
                showingFullCount = pending
            }
        }) { item in
            QuickCountView(item: item, onOpenFullCount: {
                pendingFullCountItem = item
            })
            .sheetStyle()
        }
        .sheet(item: $showingFullCount) { item in
            CountItemView(item: item)
                .sheetStyle()
        }
        .onAppear { viewModel.bind(items: items) }
        .onChange(of: items) { _, newValue in viewModel.updateItems(newValue) }
    }
}

// MARK: - Count Item Card

struct CountItemCard: View {
    let item: InventoryItem
    let countedThisSession: Bool
    var showViewOnlyLock: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Storage color stripe
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                .frame(width: 4, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    // Session checkmark — shown if counted this session
                    if countedThisSession {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.stoqlySuccess)
                            .font(.system(size: 18))
                    }
                }

                HStack(spacing: 8) {
                    // Stock status badge
                    Text(item.isOutOfStock ? "Out of Stock" : item.isLowStock ? "Low Stock" : "In Stock")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            item.isOutOfStock ? Color.stoqlyDanger.opacity(0.12) :
                            item.isLowStock ? Color.stoqlyWarning.opacity(0.12) :
                            Color.stoqlySuccess.opacity(0.10)
                        )
                        .foregroundColor(
                            item.isOutOfStock ? .red :
                            item.isLowStock ? .orange : .green
                        )
                        .cornerRadius(4)

                    Text(item.storage?.name ?? "No Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Last counted
                Text(lastCountedText(for: item))
                    .font(.caption2)
                    .foregroundColor(item.countHistory.isEmpty ? .red.opacity(0.8) : .secondary)
            }

            Spacer()

            if showViewOnlyLock {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Current quantity — right side
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.currentQuantity.smartFormatted)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(item.uom?.symbol ?? "units")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .opacity(countedThisSession ? 0.65 : 1.0)
    }

    private func lastCountedText(for item: InventoryItem) -> String {
        guard let latest = item.countHistory.sorted(by: { $0.countDate > $1.countDate }).first else {
            return "Never counted"
        }
        let days = Calendar.current.dateComponents([.day], from: latest.countDate, to: Date()).day ?? 0
        if days == 0 { return "Counted today" }
        if days == 1 { return "Counted yesterday" }
        return "Counted \(days) days ago"
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    var dot: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if dot {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Empty States

struct EmptyCountState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.stoqlySuccess)
            Text("All caught up!")
                .font(.title3).fontWeight(.semibold)
            Text("Every item has been counted recently.\nNothing needs auditing right now.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Rounded Corners Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    InventoryAppView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
        .environmentObject(AuthManager.shared)
        .environmentObject(FirestoreManager.shared)
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(TrackingPermissionManager.shared)
}
