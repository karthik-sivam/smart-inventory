import Foundation

// MARK: - AIUsageManager
//
// Tracks monthly usage of AI inventory features (voice, image, paper).
// Free users get 3 uses per feature type per calendar month.
// Pro users get unlimited uses.
//
// Usage:
//   AIUsageManager.shared.canUse(.voice, isPro: sub.isPro)
//   AIUsageManager.shared.recordUse(.image)
//   AIUsageManager.shared.remaining(.paper, isPro: false) // → 2

@MainActor
final class AIUsageManager: ObservableObject {
    // @MainActor + ObservableObject makes this type Sendable — no nonisolated(unsafe) needed.
    // The static let inherits @MainActor isolation from the class, so the init is legal here.
    static let shared = AIUsageManager()
    private init() {}

    enum FeatureType: String {
        case voice  = "stoqly_ai_voice"
        case image  = "stoqly_ai_image"
        case paper  = "stoqly_ai_paper"

        var displayName: String {
            switch self {
            case .voice: return "Voice Inventory"
            case .image: return "Photo Inventory"
            case .paper: return "Sheet Inventory"
            }
        }
    }

    static let freeLimit = 3

    // MARK: - Public API

    func canUse(_ type: FeatureType, isPro: Bool) -> Bool {
        isPro || usageThisMonth(type) < AIUsageManager.freeLimit
    }

    func remaining(_ type: FeatureType, isPro: Bool) -> Int {
        if isPro { return Int.max }
        return max(0, AIUsageManager.freeLimit - usageThisMonth(type))
    }

    func recordUse(_ type: FeatureType) {
        let key = storageKey(type)
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
        objectWillChange.send()
    }

    // MARK: - Helpers

    private func usageThisMonth(_ type: FeatureType) -> Int {
        UserDefaults.standard.integer(forKey: storageKey(type))
    }

    /// Key includes year+month so it auto-resets each calendar month
    private func storageKey(_ type: FeatureType) -> String {
        let cal = Calendar.current
        let now = Date()
        let year  = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        return "\(type.rawValue)_\(year)_\(month)"
    }
}
