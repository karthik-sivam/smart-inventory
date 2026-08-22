import Foundation
import ObjectiveC

// MARK: - Runtime language override for String Catalog / .lproj lookups

private nonisolated(unsafe) var associatedLanguageBundleKey: UInt8 = 0

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &associatedLanguageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swaps `Bundle.main` to load strings from the given language, or restores system default when `nil`.
    static func setLanguage(_ language: String?) {
        defer {
            object_setClass(Bundle.main, language == nil ? Bundle.self : LocalizedBundle.self)
        }

        guard let language, !language.isEmpty else {
            objc_setAssociatedObject(
                Bundle.main,
                &associatedLanguageBundleKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return
        }

        let bundle = Bundle.resolvedLprojBundle(for: language) ?? Bundle.main
        objc_setAssociatedObject(
            Bundle.main,
            &associatedLanguageBundleKey,
            bundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func resolvedLprojBundle(for language: String) -> Bundle? {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let prefix = language.split(separator: "-").first.map(String.init) ?? language
        if prefix != language,
           let path = Bundle.main.path(forResource: prefix, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return nil
    }
}
