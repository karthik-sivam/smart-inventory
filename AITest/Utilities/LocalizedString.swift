import Foundation

/// Resolves against the in-app language override bundle (S39).
/// Unlike `String(localized:)`, this follows the user's in-app language choice.
func L(_ key: String, _ fallback: String) -> String {
    let code = UserDefaults.standard.string(forKey: "appLanguageOverride") ?? ""
    let bundle: Bundle
    if code.isEmpty {
        bundle = .main
    } else if let override = Bundle.resolvedLprojBundle(for: code) {
        bundle = override
    } else {
        bundle = .main
    }
    return bundle.localizedString(forKey: key, value: fallback, table: nil)
}
