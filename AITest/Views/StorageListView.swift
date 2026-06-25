import SwiftUI
import SwiftData
import UIKit

struct StorageListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    @StateObject private var viewModel = StorageListViewModel()
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var teamManager = TeamManager.shared
    @State private var showingAddStorage = false
    @State private var showingEditStorage: Storage?
    @State private var showingDeleteAlert: Storage?
    @State private var showingPaywall = false
    /// Bottom toast confirming a storage deletion. Auto-clears after ~2 seconds.
    @State private var toastMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Storages")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    if subscriptionManager.isPro && teamManager.isOwner {
                        NavigationLink(destination: TeamMembersView()) {
                            Image(systemName: "person.2.fill")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Team Members")
                    }

                    if teamManager.canEdit {
                        Button(action: {
                            if viewModel.isAtFreeStorageCap {
                                showingPaywall = true
                            } else {
                                showingAddStorage = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.stoqlyPrimary)
                        }
                        .accessibilityLabel("Add Storage")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                if teamManager.isInTeamWorkspace {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("Viewing team workspace")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                }

                if let usageText = viewModel.freeStorageUsageText {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(usageText)
                                .font(.caption)
                                .foregroundColor(viewModel.isAtFreeStorageCap ? .orange : .secondary)
                            Spacer()
                            if viewModel.isAtFreeStorageCap {
                                Text("Upgrade for unlimited")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        ProgressView(
                            value: Double(storages.count),
                            total: Double(StorageListViewModel.freeStorageCap)
                        )
                        .tint(viewModel.isAtFreeStorageCap ? .orange : .blue)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                SearchBar(text: $viewModel.searchText, placeholder: "Search storages...")
                    .onChange(of: viewModel.searchText) { _, newValue in
                        viewModel.setSearchText(newValue)
                    }
                    .padding(.horizontal)
                List {
                    if viewModel.filteredStorages.isEmpty {
                        Group {
                            if viewModel.searchText.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "archivebox.fill")
                                        .font(.system(size: 64))
                                        .foregroundStyle(
                                            LinearGradient(colors: [.blue, .cyan],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )

                                    VStack(spacing: 8) {
                                        Text("Welcome to Stoqly")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .multilineTextAlignment(.center)

                                        Text("Start by creating a storage area -- a room, shelf, warehouse, or any location where you keep stock.")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                    }

                                    if teamManager.canEdit {
                                        Button(action: {
                                            if viewModel.isAtFreeStorageCap {
                                                showingPaywall = true
                                            } else {
                                                showingAddStorage = true
                                            }
                                        }) {
                                            Label("Create Your First Storage", systemImage: "plus.circle.fill")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 12)
                                                .background(Color.stoqlyPrimary)
                                                .cornerRadius(12)
                                        }
                                    }

                                    VStack(spacing: 10) {
                                        OnboardingHintRow(icon: "shippingbox", text: "Add items with quantities, SKUs, and barcodes")
                                        OnboardingHintRow(icon: "exclamationmark.triangle", text: "Get alerted when stock runs low")
                                        OnboardingHintRow(icon: "square.and.arrow.up", text: "Export reports to CSV or PDF anytime")
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                    Text("No storages found")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(viewModel.filteredStorages, id: \.id) { storage in
                            NavigationLink(destination: StorageDetailView(storage: storage)) {
                                StorageCard(storage: storage)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if teamManager.canDeleteStorage {
                                    Button(role: .destructive) {
                                        showingDeleteAlert = storage
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                                if teamManager.canEdit {
                                    Button {
                                        showingEditStorage = storage
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddStorage) {
            AddStorageView()
                .sheetStyle()
        }
        .sheet(item: $showingEditStorage) { storage in
            EditStorageView(storage: storage)
                .sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(featureContext: "Unlimited Storages", source: "storage_limit")
                .sheetStyle()
        }
        .alert("Delete Storage", isPresented: Binding(
            get: { showingDeleteAlert != nil },
            set: { if !$0 { showingDeleteAlert = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                showingDeleteAlert = nil
            }
            Button("Delete", role: .destructive) {
                if let storage = showingDeleteAlert {
                    let name = storage.name
                    viewModel.deleteStorage(storage)
                    toastMessage = "\"\(name)\" deleted"
                }
                showingDeleteAlert = nil
            }
        } message: {
            if let storage = showingDeleteAlert {
                Text("Are you sure you want to delete '\(storage.name)'? This will also delete all items in this storage.")
            }
        }
        .onAppear {
            viewModel.bind(modelContext: modelContext, storages: storages)
        }
        .onChange(of: storages) { _, newValue in
            viewModel.updateStorages(newValue)
        }
        .toast(message: $toastMessage)
    }
}

struct StorageCard: View {
    let storage: Storage
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: storage.color) ?? .blue)
                .frame(width: 4, height: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(storage.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if !storage.location.isEmpty {
                    Text(storage.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !storage.storageDescription.isEmpty {
                    Text(storage.storageDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(storage.itemCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if storage.totalQuantity > 0 {
                    Text("\(storage.totalQuantity.smartFormatted) units")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct AddStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]

    /// Optional callback — called with the newly created storage before dismissing.
    /// Used by callers (e.g. BulkImportView) that want to auto-select the new storage.
    var onStorageAdded: ((Storage) -> Void)? = nil

    @State private var name = ""
    @State private var location = ""
    @State private var description = ""
    @State private var selectedColor = "#007AFF"

    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#8E8E93", "#000000"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Storage Information")) {
                    TextField("Storage Name", text: $name)
                    TextField("Location (Optional)", text: $location)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.stoqlyPrimary : Color.clear,
                                                    lineWidth: 3)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Storage")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveStorage()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    private func saveStorage() {
        guard storages.count < StorageListViewModel.freeStorageCap
                || SubscriptionManager.shared.isPro else {
            dismiss()
            return
        }
        let storage = Storage(
            name: name,
            location: location,
            description: description,
            color: selectedColor
        )

        modelContext.insert(storage)
        modelContext.safeSave(context: "addStorage")

        let storageEvent = ActivityEvent(
            eventType: "StorageCreated",
            itemName: "",
            storageName: storage.name,
            performedBy: AuthManager.shared.actorName
        )
        modelContext.insert(storageEvent)
        modelContext.safeSave(context: "StorageCreated activity event")
        FirestoreManager.shared.syncActivity(storageEvent)

        // Mirror to Firestore cloud
        FirestoreManager.shared.syncStorage(storage)

        // Track completion for ad system
        AdManager.shared.recordCompletion(event: .storageCreated)

        AnalyticsManager.shared.track(.storageCreated(color: storage.color))

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onStorageAdded?(storage)
        dismiss()
    }
}

private struct OnboardingHintRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.stoqlyPrimary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// Extension to convert hex color to SwiftUI Color
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    StorageListView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 