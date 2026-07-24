import Foundation
import Speech

// MARK: - SpeechEnginePicker

enum VoiceSpeechEngine: Equatable {
    case apple(localeID: String)
    case sarvam(languageCode: String)
    case unavailable
}

enum SpeechEnginePicker {
    private static let indianLanguageCodes: Set<String> = ["hi", "ta", "te", "kn", "ml"]

    /// Maps app language code (from LocalizationManager) to a speech locale identifier.
    static func voiceLocaleID(for appLanguageCode: String?) -> String {
        let code = normalizedLanguageCode(appLanguageCode)
        switch code {
        case "hi": return "hi-IN"
        case "ta": return "ta-IN"
        case "te": return "te-IN"
        case "kn": return "kn-IN"
        case "ml": return "ml-IN"
        case "ar": return "ar-SA"
        case "es": return "es-ES"
        case "pt-BR", "pt": return "pt-BR"
        case "fr": return "fr-FR"
        case "zh-Hans", "zh": return "zh-CN"
        case "id": return "id-ID"
        case "de": return "de-DE"
        case "ru": return "ru-RU"
        case "ja": return "ja-JP"
        case "en":
            return Locale.current.region?.identifier == "IN" ? "en-IN" : "en-US"
        default:
            return Locale.current.identifier
        }
    }

    static func pickEngine(for appLanguageCode: String?) -> VoiceSpeechEngine {
        let localeID = voiceLocaleID(for: appLanguageCode)
        let locale = Locale(identifier: localeID)
        let lang = normalizedLanguageCode(appLanguageCode ?? locale.language.languageCode?.identifier)

        if AppleSpeechTranscriber.isLocaleSupported(localeID) {
            let best = AppleSpeechTranscriber.bestLocaleID(preferred: localeID)
            return .apple(localeID: best)
        }

        if indianLanguageCodes.contains(lang), SecretsManager.hasSarvamKey {
            return .sarvam(languageCode: localeID)
        }

        return .unavailable
    }

    /// Display label for the active voice locale pill.
    static func localeDisplayName(for localeID: String) -> String {
        switch localeID {
        case "en-IN": return "English (India)"
        case "en-US": return "English (US)"
        case "en-GB": return "English (UK)"
        case "hi-IN": return "हिन्दी"
        case "ta-IN": return "தமிழ்"
        case "te-IN": return "తెలుగు"
        case "kn-IN": return "ಕನ್ನಡ"
        case "ml-IN": return "മലയാളം"
        case "ar-SA": return "العربية"
        case "es-ES": return "Español"
        case "pt-BR": return "Português"
        case "fr-FR": return "Français"
        case "zh-CN": return "简体中文"
        case "id-ID": return "Bahasa Indonesia"
        case "de-DE": return "Deutsch"
        case "ru-RU": return "Русский"
        case "ja-JP": return "日本語"
        default:
            return Locale(identifier: localeID).localizedString(forIdentifier: localeID) ?? localeID
        }
    }

    static func englishLocalePills() -> [(String, String)] {
        [("en-IN", "English (India)"), ("en-US", "English (US)"), ("en-GB", "English (UK)")]
    }

    private static func normalizedLanguageCode(_ code: String?) -> String {
        guard let code, !code.isEmpty else {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        if code.hasPrefix("zh") { return "zh-Hans" }
        if code.hasPrefix("pt") { return "pt-BR" }
        return code.split(separator: "-").first.map(String.init) ?? code
    }
}
