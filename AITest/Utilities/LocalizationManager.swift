import SwiftUI

struct LanguageOption: Identifiable, Hashable {
    let code: String?
    let englishName: String
    let nativeName: String
    let isRTL: Bool

    var id: String { code ?? "systemDefault" }
}

enum LanguageCatalog {
    static func load() -> (systemDefault: LanguageOption, languages: [LanguageOption]) {
        guard
            let url = Bundle.main.url(forResource: "language_display_names", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let system = json["systemDefault"] as? [String: Any],
            let languagesJSON = json["languages"] as? [[String: Any]]
        else {
            return fallback
        }

        let systemDefault = LanguageOption(
            code: nil,
            englishName: system["englishName"] as? String ?? "System Default",
            nativeName: system["nativeName"] as? String ?? "System Default",
            isRTL: false
        )

        let languages = languagesJSON.compactMap { entry -> LanguageOption? in
            guard let code = entry["code"] as? String else { return nil }
            return LanguageOption(
                code: code,
                englishName: entry["englishName"] as? String ?? code,
                nativeName: entry["nativeName"] as? String ?? code,
                isRTL: entry["rtl"] as? Bool ?? false
            )
        }

        return (systemDefault, languages)
    }

    private static let fallback: (systemDefault: LanguageOption, languages: [LanguageOption]) = (
        LanguageOption(code: nil, englishName: "System Default", nativeName: "System Default", isRTL: false),
        [
            LanguageOption(code: "en", englishName: "English", nativeName: "English", isRTL: false),
            LanguageOption(code: "hi", englishName: "Hindi", nativeName: "हिन्दी", isRTL: false),
            LanguageOption(code: "ar", englishName: "Arabic", nativeName: "العربية", isRTL: true)
        ]
    )
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let overrideKey = "appLanguageOverride"
    private static let appleLanguagesKey = "AppleLanguages"

    @AppStorage(overrideKey) private var storedCode: String = ""
    @Published var refreshID = UUID()

    private let catalog = LanguageCatalog.load()

    var currentCode: String? {
        storedCode.isEmpty ? nil : storedCode
    }

    init() {
        if let code = currentCode {
            Bundle.setLanguage(code)
        }
    }

    func setLanguage(_ code: String?) {
        if let code, !code.isEmpty {
            storedCode = code
            UserDefaults.standard.set([code], forKey: Self.appleLanguagesKey)
            Bundle.setLanguage(code)
        } else {
            storedCode = ""
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
            Bundle.setLanguage(nil)
        }
        refreshID = UUID()
        AppWindowCoordinator.reRootWindow()
    }

    func effectiveLocale() -> Locale {
        Locale(identifier: currentCode ?? Locale.current.identifier)
    }

    var layoutDirection: LayoutDirection {
        effectiveLocale().language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    func currentDisplayName() -> String {
        if let code = currentCode,
           let match = catalog.languages.first(where: { $0.code == code }) {
            return match.nativeName
        }
        return catalog.systemDefault.nativeName
    }

    var systemDefaultOption: LanguageOption { catalog.systemDefault }
    var languageOptions: [LanguageOption] { catalog.languages }

    func isSelected(_ option: LanguageOption) -> Bool {
        if option.code == nil {
            return currentCode == nil
        }
        return currentCode == option.code
    }
}
