import SwiftUI
import SwiftData

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

    // Onboarding: shown once on first ever launch
    @State private var showOnboarding = !UserDefaults.hasCompletedOnboarding

    // Paywall
    @State private var showPaywall = false

    // Prevents running startup sync more than once per in-memory session.
    // Deliberately NOT persisted — after reinstall we always want a fresh pull.
    @State private var hasSyncedThisSession = false

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
        // Paywall sheet
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task {
            // Ask ATT first, then prompt for notifications.
            await trackingManager.requestPermissionIfNeeded()
            NotificationManager.shared.requestPermission()
        }
        // Triggered whenever auth state changes (sign in / sign out)
        .onChange(of: authManager.isAuthenticated) { isAuthed in
            if isAuthed { runStartupSync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            NotificationManager.shared.checkAndNotifyLowStock(items: items)
        }
        // Also run on appear in case the user was already signed in
        // when the app launched (persisted session)
        .onAppear {
            if authManager.isAuthenticated { runStartupSync() }
        }
    }

    // MARK: - Startup Sync Logic

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
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // Content
            Group {
                switch selectedTab {
                case 0:
                    DashboardView()
                        .environmentObject(currencyManager)
                case 1:
                    StorageListView()
                        .environmentObject(currencyManager)
                case 2:
                    ItemListView()
                        .environmentObject(currencyManager)
                case 3:
                    CountView()
                        .environmentObject(currencyManager)
                case 4:
                    ProfileView()
                        .environmentObject(firestoreManager)
                        .environmentObject(subscriptionManager)
                default:
                    DashboardView()
                        .environmentObject(currencyManager)
                }
            }

            // Custom Bottom Tab Bar
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Sync status strip — visible when actively syncing
                    if case .syncing = firestoreManager.syncState {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Syncing to cloud…")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Tab bar
                    HStack(spacing: 0) {
                        TabBarButton(icon: "house.fill",          title: "Dashboard", isSelected: selectedTab == 0) { selectedTab = 0 }
                        TabBarButton(icon: "archivebox.fill",     title: "Storages",  isSelected: selectedTab == 1) { selectedTab = 1 }
                        TabBarButton(icon: "cube.box.fill",       title: "Items",     isSelected: selectedTab == 2) { selectedTab = 2 }
                        TabBarButton(icon: "list.clipboard.fill", title: "Count",     isSelected: selectedTab == 3) { selectedTab = 3 }
                        TabBarButton(icon: "person.circle.fill",  title: "Profile",   isSelected: selectedTab == 4) { selectedTab = 4 }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                }
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .animation(.easeInOut(duration: 0.3), value: firestoreManager.syncState)
        }
    }
}

// MARK: - Tab Bar Button

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .gray)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Inventory Count")
                        .font(.title2)
                        .fontWeight(.bold)

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
                            color: .blue
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

                // Search
                SearchBar(text: $viewModel.searchText, placeholder: "Search items to count…")
                    .onChange(of: viewModel.searchText) { viewModel.setSearchText($0) }
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Item list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.filteredItems.isEmpty {
                            EmptyCountState()
                        } else {
                            ForEach(viewModel.filteredItems.sorted(by: { $0.name < $1.name }), id: \.id) { item in
                                Button {
                                    showingQuickCount = item
                                } label: {
                                    CountItemCard(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .padding(.top, 16)
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $showingQuickCount, onDismiss: {
            if let pending = pendingFullCountItem {
                pendingFullCountItem = nil
                showingFullCount = pending
            }
        }) { item in
            QuickCountView(item: item, onOpenFullCount: {
                pendingFullCountItem = item
            })
        }
        .sheet(item: $showingFullCount) { item in
            CountItemView(item: item)
        }
        .onAppear { viewModel.bind(items: items) }
        .onChange(of: items) { viewModel.updateItems($0) }
    }
}

// MARK: - Count Item Card

struct CountItemCard: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                .frame(width: 4, height: 50)

            Circle()
                .fill(item.isOutOfStock ? Color.red : (item.isLowStock ? Color.orange : Color.green))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                HStack {
                    Text("SKU: \(item.sku)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(item.storage?.name ?? "No Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Current: \(String(format: "%.1f", item.currentQuantity)) \(item.uom?.symbol ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "list.clipboard")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Count")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
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
            Image(systemName: "list.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No items to count")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text("Add items to your storages to start counting inventory.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
