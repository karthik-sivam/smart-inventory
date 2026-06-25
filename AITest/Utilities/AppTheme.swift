import SwiftUI

// MARK: - AppTheme
//
// Central colour system for Stoqly.
// Palette: indigo primary + teal accent — modern B2B feel.
//
// Usage:
//   .foregroundColor(.stoqlyPrimary)
//   Color.stoqlySuccess
//   AppTheme.cardBackground
//
// Semantic rules:
//   stoqlyPrimary  — interactive elements, links, selected states, nav icons
//   stoqlyAccent   — secondary actions, highlights, tags
//   stoqlySuccess  — in-stock, positive delta, confirmation
//   stoqlyWarning  — low stock, expiring soon, caution
//   stoqlyDanger   — out of stock, delete, destructive actions
//   stoqlyNeutral  — borders, dividers, muted backgrounds

extension Color {

    // MARK: - Primary palette

    /// Indigo #4F46E5 — main interactive / brand colour
    static let stoqlyPrimary = Color(red: 0.310, green: 0.275, blue: 0.898)

    /// Teal #0D9488 — secondary accent
    static let stoqlyAccent = Color(red: 0.051, green: 0.580, blue: 0.533)

    // MARK: - Semantic status colours
    // These intentionally replace plain .green / .orange / .red
    // so they adapt nicely in dark mode and stay on-brand.

    /// Emerald #10B981 — in stock, positive, success
    static let stoqlySuccess = Color(red: 0.063, green: 0.725, blue: 0.506)

    /// Amber #F59E0B — low stock, expiring soon, warning
    static let stoqlyWarning = Color(red: 0.961, green: 0.620, blue: 0.043)

    /// Rose #F43F5E — out of stock, error, destructive
    static let stoqlyDanger = Color(red: 0.957, green: 0.247, blue: 0.369)

    /// Sky #0EA5E9 — informational, neutral highlight
    static let stoqlyInfo = Color(red: 0.055, green: 0.647, blue: 0.914)

    // MARK: - Surface colours

    /// Card / row background — adapts to light/dark
    static let stoqlyCard = Color(UIColor.secondarySystemBackground)

    /// Subtle grouped background
    static let stoqlyGrouped = Color(UIColor.systemGroupedBackground)

    // MARK: - Soft tints (used for badge backgrounds, icon fills)

    static var stoqlyPrimaryTint: Color { stoqlyPrimary.opacity(0.12) }
    static var stoqlyAccentTint:  Color { stoqlyAccent.opacity(0.12) }
    static var stoqlySuccessTint: Color { stoqlySuccess.opacity(0.12) }
    static var stoqlyWarningTint: Color { stoqlyWarning.opacity(0.12) }
    static var stoqlyDangerTint:  Color { stoqlyDanger.opacity(0.12) }
    static var stoqlyInfoTint:    Color { stoqlyInfo.opacity(0.12) }
}

// MARK: - AppTheme namespace (layout + typography helpers)

enum AppTheme {
    // Corner radii
    static let radiusSm: CGFloat  = 8
    static let radiusMd: CGFloat  = 12
    static let radiusLg: CGFloat  = 16
    static let radiusXl: CGFloat  = 20

    // Shadows
    static func cardShadow() -> some View {
        RoundedRectangle(cornerRadius: radiusMd)
            .fill(Color.stoqlyCard)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // KPI card gradient pairs — professional teal / gold / slate palette.
    // Semantic meaning: teal = positive/brand, gold = caution/attention,
    //                   crimson = danger, emerald = value/growth.
    // Deep starting tones keep the look premium rather than primary-school-bright.
    static let kpiGradients: [(Color, Color)] = [
        // 0: Deep Ocean → Brand Teal          (Storages)
        (Color(red: 0.043, green: 0.239, blue: 0.208), Color(red: 0.051, green: 0.580, blue: 0.533)),
        // 1: Midnight Navy → Steel Teal        (Items — depth, trust)
        (Color(red: 0.059, green: 0.149, blue: 0.259), Color(red: 0.047, green: 0.388, blue: 0.545)),
        // 2: Cognac → Rich Gold                (Low Stock — warm premium warning)
        (Color(red: 0.420, green: 0.196, blue: 0.000), Color(red: 0.784, green: 0.455, blue: 0.000)),
        // 3: Deep Burgundy → Muted Crimson     (Out of Stock — serious, not garish)
        (Color(red: 0.271, green: 0.039, blue: 0.039), Color(red: 0.600, green: 0.106, blue: 0.106)),
        // 4: Forest → Emerald Teal             (Total Value — growth, money)
        (Color(red: 0.024, green: 0.306, blue: 0.231), Color(red: 0.020, green: 0.588, blue: 0.412)),
        // 5: Dark Bronze → Warm Amber          (Expiring Soon — urgency without alarm)
        (Color(red: 0.361, green: 0.165, blue: 0.000), Color(red: 0.706, green: 0.325, blue: 0.035)),
    ]
}

// MARK: - Gradient button style helper

extension View {
    /// Primary filled button — indigo gradient, white text, rounded
    func stoqlyButtonStyle(gradient: Bool = true) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                gradient
                ? AnyView(LinearGradient(
                    colors: [Color.stoqlyPrimary, Color(red: 0.400, green: 0.200, blue: 0.900)],
                    startPoint: .leading,
                    endPoint: .trailing))
                : AnyView(Color.stoqlyPrimary)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
    }
}
