import Foundation

// MARK: - SecretsManager
//
// Reads sensitive keys from Secrets.plist (not committed to source control).
//
// Setup:
//   1. In Xcode, right-click AITest/ → New File → Property List → name it "Secrets.plist"
//   2. Add one row:  Key = ANTHROPIC_API_KEY   Type = String   Value = sk-ant-api03-...
//   3. Make sure Secrets.plist is in .gitignore
//
// Usage:
//   let key = SecretsManager.anthropicAPIKey

enum SecretsManager {
    private nonisolated(unsafe) static let plist: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dict
    }()

    /// Anthropic API key for Claude AI features (voice, image, paper inventory).
    /// Returns nil if Secrets.plist is not present or key is missing.
    static var anthropicAPIKey: String? {
        plist?["ANTHROPIC_API_KEY"] as? String
    }

    /// True when the Anthropic key is present and non-empty
    static var hasAnthropicKey: Bool {
        guard let key = anthropicAPIKey, !key.isEmpty else { return false }
        return true
    }

    /// Amplitude API key for product analytics.
    /// Add  Key = AMPLITUDE_API_KEY  Type = String  Value = <your key>  to Secrets.plist.
    static var amplitudeAPIKey: String? {
        plist?["AMPLITUDE_API_KEY"] as? String
    }
}
