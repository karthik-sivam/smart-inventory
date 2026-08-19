import Foundation

/// User-facing dates/times respect the app language override (S21-4).
enum AppLocaleFormatting {
    private static let overrideKey = "appLanguageOverride"

    static var locale: Locale {
        let code = UserDefaults.standard.string(forKey: overrideKey) ?? ""
        if code.isEmpty {
            return Locale.current
        }
        return Locale(identifier: code)
    }

    static func relativeString(from date: Date, relativeTo reference: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    static func abbreviatedDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(locale)
        )
    }

    static func abbreviatedDateTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
    }

    static func sectionDayTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return L("Today", "Today")
        }
        if cal.isDateInYesterday(date) {
            return L("Yesterday", "Yesterday")
        }
        return abbreviatedDate(date)
    }
}

/// Localize a persisted movement type raw value for display (raw values stay unchanged in storage).
enum MovementTypeDisplay {
    static func localizedLabel(for rawValue: String) -> String {
        if let type = MovementTypeIn(rawValue: rawValue) {
            return type.localizedTitle
        }
        if let type = MovementTypeOut(rawValue: rawValue) {
            return type.localizedTitle
        }
        return rawValue
    }
}
