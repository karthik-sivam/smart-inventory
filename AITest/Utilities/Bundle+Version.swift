import Foundation

extension Bundle {
    /// The app's real marketing version + build number, e.g. "1.3 (45)".
    /// Reads CFBundleShortVersionString / CFBundleVersion so Settings & Profile
    /// always reflect the shipped version instead of a hardcoded string.
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
