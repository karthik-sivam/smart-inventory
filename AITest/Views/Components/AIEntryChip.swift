import SwiftUI

// MARK: - Session dismiss (in-memory only)

/// Remembers which AI entry chips the user dismissed this process lifetime.
/// Not persisted — relaunching the app restores the chips.
@MainActor
final class AIEntryChipSessionStore: ObservableObject {
    static let shared = AIEntryChipSessionStore()
    private init() {}

    @Published private(set) var dismissedFeatures: Set<String> = []

    func isDismissed(_ feature: AIEntryChipFeature) -> Bool {
        dismissedFeatures.contains(feature.analyticsValue)
    }

    func dismiss(_ feature: AIEntryChipFeature) {
        dismissedFeatures.insert(feature.analyticsValue)
    }
}

// MARK: - Feature

enum AIEntryChipFeature: String {
    case smartCount = "smart_count"
    case smartSales = "smart_sales"
    // TODO(iOS-C1): add `smartPurchase` when Manual Purchase Entry ships,
    // with copy "Or scan an invoice with Smart Purchase →" on that screen.

    var analyticsValue: String { rawValue }

    var titleKey: String {
        switch self {
        case .smartCount: return "add_item.ai_chip.smart_count"
        case .smartSales: return "sales_manual.ai_chip.smart_sales"
        }
    }

    var titleFallback: String {
        switch self {
        case .smartCount: return "Or scan a shelf with Smart Count →"
        case .smartSales: return "Or scan a bill with Smart Sales →"
        }
    }
}

// MARK: - Visibility policy (testable)

enum AIEntryChipPolicy {
    /// Free users see the chip only while quota remains.
    /// SmartCount: any of voice / photo / sheet still has a free use this month.
    /// SmartSales: always (F5 — no free-tier cap).
    /// Pro users always see the chip. Session dismiss hides it until relaunch.
    static func isVisible(
        feature: AIEntryChipFeature,
        isPro: Bool,
        dismissedThisSession: Bool,
        hasSmartCountQuotaRemaining: Bool
    ) -> Bool {
        guard !dismissedThisSession else { return false }
        if isPro { return true }
        switch feature {
        case .smartCount:
            return hasSmartCountQuotaRemaining
        case .smartSales:
            return true
        }
    }
}

// MARK: - Chip

/// Subtle discovery CTA that routes from a manual entry screen to the matching AI flow.
struct AIEntryChip: View {
    enum Style {
        case plain
        case formSection
    }

    let feature: AIEntryChipFeature
    let screen: String
    var style: Style = .plain
    let onTap: () -> Void

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared
    @ObservedObject private var sessionStore: AIEntryChipSessionStore = AIEntryChipSessionStore.shared
    @State private var didTrackShown = false

    private var isVisible: Bool {
        AIEntryChipPolicy.isVisible(
            feature: feature,
            isPro: subscriptionManager.isPro,
            dismissedThisSession: sessionStore.isDismissed(feature),
            hasSmartCountQuotaRemaining: usageManager.hasSmartCountQuotaRemaining(
                isPro: subscriptionManager.isPro
            )
        )
    }

    var body: some View {
        if isVisible {
            switch style {
            case .plain:
                chip
            case .formSection:
                Section {
                    chip
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Button(action: handleTap) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.stoqlyAccent)
                    Text(L(feature.titleKey, feature.titleFallback))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiEntryChip_\(feature.analyticsValue)")

            Button(action: handleDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ai_chip.dismiss.a11y_label", "Dismiss"))
            .accessibilityIdentifier("aiEntryChipDismiss_\(feature.analyticsValue)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.stoqlyAccentTint)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .onAppear(perform: trackShownIfNeeded)
    }

    private func handleTap() {
        AnalyticsManager.shared.track(
            .aiEntryChipTapped(screen: screen, feature: feature.analyticsValue)
        )
        onTap()
    }

    private func handleDismiss() {
        sessionStore.dismiss(feature)
    }

    private func trackShownIfNeeded() {
        guard !didTrackShown else { return }
        didTrackShown = true
        AnalyticsManager.shared.track(
            .aiEntryChipShown(screen: screen, feature: feature.analyticsValue)
        )
    }
}
