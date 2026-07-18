import SwiftUI

/// A persistent native upsell bar shown to free users.
/// Place it outside any ScrollView so it stays pinned below the navigation header.
/// Tapping it posts "stoqly.showPaywall" so the nearest InventoryAppView can open the paywall.
struct ProUpgradeStrip: View {
    let onTap: () -> Void

    private let teal = Color(red: 0.051, green: 0.580, blue: 0.533)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(teal)
                Text("Go Pro — Remove Ads & Unlock Everything")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text("See Plans")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(teal)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(teal.opacity(0.08))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(teal.opacity(0.2)),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}
