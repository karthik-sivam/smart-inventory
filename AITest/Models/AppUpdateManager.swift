import Foundation
import FirebaseFirestore

/// Server-driven minimum-version gate.
///
/// IMPORTANT — what this can and cannot do. The check has to exist inside the
/// installed binary, so this only ever governs builds that shipped with it.
/// Releasing it in 1.5 means 1.5 and later can be force-updated; builds at or
/// below 1.4 contain no gate and can never be blocked, no matter what is
/// configured server-side. There is no App Store or OS mechanism to force an
/// already-installed app to update.
///
/// Fails OPEN by design. A missing document, a permission error, malformed
/// values or no network all resolve to "not blocked". A version gate that fails
/// closed turns any backend hiccup into a bricked app for every user at once.
@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    /// Set only when the running build is below the configured minimum.
    @Published private(set) var requirement: UpdateRequirement?

    struct UpdateRequirement: Equatable, Identifiable {
        var id: String { minimumVersion }

        let minimumVersion: String
        /// Server-supplied copy. Optional — when absent the app uses its own
        /// localized string, which is preferable because the server message
        /// cannot be translated into the user's language.
        let message: String?
        let storeURL: URL
    }

    /// `apps.apple.com/in/app/stoqly-smart-inventory/id6763451242`
    private static let appStoreID = "6763451242"
    private static let fallbackStoreURL = URL(
        string: "itms-apps://apps.apple.com/app/id\(appStoreID)"
    )!

    private let db = Firestore.firestore()
    private var isChecking = false

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Safe to call on every launch and foreground — concurrent calls collapse.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let snapshot = try? await db.collection("config").document("appVersion").getDocument(),
              let data = snapshot.data() else {
            // No document, or rules deny the read: treat as "no requirement".
            requirement = nil
            return
        }

        guard let minimum = (data["minimumSupportedVersion"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !minimum.isEmpty,
              Self.isVersion(currentVersion, olderThan: minimum) else {
            requirement = nil
            return
        }

        let message = (data["updateMessage"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storeURL = (data["storeURL"] as? String).flatMap(URL.init(string:))
            ?? Self.fallbackStoreURL

        requirement = UpdateRequirement(
            minimumVersion: minimum,
            message: (message?.isEmpty == false) ? message : nil,
            storeURL: storeURL
        )
    }

    // MARK: - Version comparison

    /// Numeric, component-wise comparison. String comparison is wrong here:
    /// "1.10" sorts before "1.9" lexically but is the newer release. Missing
    /// components count as zero, so "1.5" == "1.5.0".
    ///
    /// Anything unparseable returns false — an unreadable version must never
    /// lock someone out.
    static func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
        let a = numericComponents(lhs)
        let b = numericComponents(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }

        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private static func numericComponents(_ version: String) -> [Int] {
        let parts = version.split(separator: ".")
        guard !parts.isEmpty else { return [] }
        var out: [Int] = []
        for part in parts {
            // Tolerate suffixes like "1.6-beta2" by taking the leading digits.
            let digits = part.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { return [] }
            out.append(value)
        }
        return out
    }
}
