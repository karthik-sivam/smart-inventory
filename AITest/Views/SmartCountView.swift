import SwiftUI
import SwiftData

// MARK: - SmartCountView
//
// Entry point shown when user taps "Smart Count" (sparkles icon) from
// StorageDetailView or the Count tab.
//
// Presents three AI-powered input modes as cards:
//   • Voice   — speak items and quantities
//   • Photo   — photograph a single product
//   • Sheet   — photograph a handwritten/printed inventory list
//
// Free users see remaining uses per mode. Pro users see unlimited.

struct SmartCountView: View {
    var preselectedStorage: Storage? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    // @ObservedObject, not @StateObject — AIUsageManager.shared is a pre-existing
    // @MainActor singleton; @StateObject would incorrectly take ownership of it.
    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    @State private var selectedStorage: Storage?
    @State private var showingVoice  = false
    @State private var showingImage  = false
    @State private var showingPaper  = false
    @State private var showingPaywall = false

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.stoqlyPrimary, .stoqlyAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Smart Count")
                            .font(.title2).fontWeight(.bold)
                        Text("Use AI to take inventory faster — speak, photograph, or upload a sheet. Review everything before it's saved.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal)

                    // Storage picker — required before choosing a mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Count into")
                            .font(.subheadline).fontWeight(.semibold)
                        if storages.isEmpty {
                            Text("No storages yet — add one first.")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Picker("Storage", selection: $selectedStorage) {
                                Text("Select storage").tag(Optional<Storage>.none)
                                ForEach(storages) { s in
                                    Text(s.name).tag(Optional(s))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.stoqlyPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.stoqlyCard)
                            .cornerRadius(AppTheme.radiusMd)
                        }
                        if !storages.isEmpty && selectedStorage == nil {
                            Text("Select a storage to enable Smart Count modes.")
                                .font(.caption)
                                .foregroundColor(.stoqlyWarning)
                        }
                    }
                    .padding(.horizontal)

                    // Mode cards
                    modeCard(
                        icon: "mic.fill",
                        iconColor: .stoqlyPrimary,
                        title: "Voice Inventory",
                        description: "Say item names and quantities naturally. \"5 kg of flour, 3 bottles of olive oil…\"",
                        featureType: .voice,
                        action: {
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "voice"))
                            showingVoice = true
                        }
                    )

                    modeCard(
                        icon: "camera.fill",
                        iconColor: .stoqlyAccent,
                        title: "Photo Inventory",
                        description: "Point your camera at any product. AI identifies it and lets you log the count.",
                        featureType: .image,
                        action: {
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "photo"))
                            showingImage = true
                        }
                    )

                    modeCard(
                        icon: "doc.text.viewfinder",
                        iconColor: .stoqlyInfo,
                        title: "Sheet Inventory",
                        description: "Photograph a handwritten or printed inventory list. AI extracts all rows for you to review.",
                        featureType: .paper,
                        action: {
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "sheet"))
                            showingPaper = true
                        }
                    )

                    // Pro upsell if on free tier
                    if !subscriptionManager.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.stoqlyWarning)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Upgrade to Pro for unlimited Smart Count")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("Free tier: 3 uses per feature per month")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Upgrade") { showingPaywall = true }
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.stoqlyWarning)
                        }
                        .padding(14)
                        .background(Color.stoqlyWarningTint)
                        .cornerRadius(AppTheme.radiusMd)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Smart Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedStorage == nil, let preselectedStorage {
                    selectedStorage = preselectedStorage
                }
                AnalyticsManager.shared.track(.smartCountOpened)
            }
        }
        .sheet(isPresented: $showingVoice) {
            VoiceInventoryView(preselectedStorage: selectedStorage).sheetStyle()
        }
        .sheet(isPresented: $showingImage) {
            ImageInventoryView(preselectedStorage: selectedStorage).sheetStyle()
        }
        .sheet(isPresented: $showingPaper) {
            PaperInventoryView(preselectedStorage: selectedStorage).sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "ai_limit").sheetStyle()
        }
    }

    // MARK: - Mode card

    private func modeCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        featureType: AIUsageManager.FeatureType,
        action: @escaping () -> Void
    ) -> some View {
        let isPro = subscriptionManager.isPro
        let remaining = usageManager.remaining(featureType, isPro: isPro)
        let canUse = usageManager.canUse(featureType, isPro: isPro)
        let isEnabled = isStorageSelected && canUse

        return Button(action: action) {
            HStack(spacing: 16) {
                // Icon bubble
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isEnabled ? 0.12 : 0.06))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isEnabled ? iconColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if !isPro {
                        HStack(spacing: 4) {
                            Image(systemName: canUse ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(canUse ? .stoqlySuccess : .stoqlyDanger)
                            Text(canUse ? "\(remaining) use\(remaining == 1 ? "" : "s") remaining" : "Limit reached — upgrade to Pro")
                                .font(.caption2)
                                .foregroundColor(canUse ? .stoqlySuccess : .stoqlyDanger)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.stoqlyCard)
            .cornerRadius(AppTheme.radiusLg)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}
