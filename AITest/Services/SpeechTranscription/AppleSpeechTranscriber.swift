import Foundation
import Speech

/// On-device / Apple cloud speech via SFSpeechRecognizer.
enum AppleSpeechTranscriber: SpeechTranscriber {
    static func supports(locale: Locale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable
    }

    static func isLocaleSupported(_ localeID: String) -> Bool {
        let locale = Locale(identifier: localeID)
        let supported = SFSpeechRecognizer.supportedLocales()
        if supported.contains(where: { $0.identifier == localeID }) { return true }
        let lang = locale.language.languageCode?.identifier ?? ""
        return supported.contains { $0.language.languageCode?.identifier == lang }
    }

    /// Best Apple locale for a language code (e.g. hi -> hi-IN if available).
    static func bestLocaleID(preferred localeID: String) -> String {
        let locale = Locale(identifier: localeID)
        let supported = SFSpeechRecognizer.supportedLocales()
        if supported.contains(where: { $0.identifier == localeID }) {
            return localeID
        }
        let lang = locale.language.languageCode?.identifier ?? localeID
        if let match = supported.first(where: { $0.language.languageCode?.identifier == lang }) {
            return match.identifier
        }
        return localeID
    }
}
