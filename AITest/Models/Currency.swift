import Foundation

struct Currency: Identifiable, Codable, Hashable {
    var id: String { code }
    let code: String
    let symbol: String
    let name: String
    
    static let currencies = [
        Currency(code: "USD", symbol: "$", name: "US Dollar"),
        Currency(code: "EUR", symbol: "€", name: "Euro"),
        Currency(code: "GBP", symbol: "£", name: "British Pound"),
        Currency(code: "JPY", symbol: "¥", name: "Japanese Yen"),
        Currency(code: "AUD", symbol: "A$", name: "Australian Dollar"),
        Currency(code: "CAD", symbol: "C$", name: "Canadian Dollar"),
        Currency(code: "CHF", symbol: "Fr", name: "Swiss Franc"),
        Currency(code: "CNY", symbol: "¥", name: "Chinese Yuan"),
        Currency(code: "SEK", symbol: "kr", name: "Swedish Krona"),
        Currency(code: "NZD", symbol: "NZ$", name: "New Zealand Dollar"),
        Currency(code: "MXN", symbol: "$", name: "Mexican Peso"),
        Currency(code: "SGD", symbol: "S$", name: "Singapore Dollar"),
        Currency(code: "HKD", symbol: "HK$", name: "Hong Kong Dollar"),
        Currency(code: "NOK", symbol: "kr", name: "Norwegian Krone"),
        Currency(code: "KRW", symbol: "₩", name: "South Korean Won"),
        Currency(code: "TRY", symbol: "₺", name: "Turkish Lira"),
        Currency(code: "RUB", symbol: "₽", name: "Russian Ruble"),
        Currency(code: "INR", symbol: "₹", name: "Indian Rupee"),
        Currency(code: "BRL", symbol: "R$", name: "Brazilian Real"),
        Currency(code: "ZAR", symbol: "R", name: "South African Rand")
    ]
}

@MainActor
class CurrencyManager: ObservableObject {
    @Published var selectedCurrency: Currency {
        didSet {
            saveCurrency()
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let currencyKey = "selectedCurrency"
    private let manuallySetCurrencyKey = "stoqly_hasManuallySetCurrency"
    private let dismissedLocaleChangeKey = "stoqly_dismissedLocaleChangeFor"
    
    init() {
        if let data = userDefaults.data(forKey: currencyKey),
           let currency = try? JSONDecoder().decode(Currency.self, from: data) {
            selectedCurrency = currency
        } else {
            let localeCode = Locale.current.currency?.identifier ?? ""
            if let match = Currency.currencies.first(where: { $0.code == localeCode }) {
                selectedCurrency = match
            } else {
                selectedCurrency = Currency.currencies.first(where: { $0.code == "USD" }) ?? Currency.currencies[0]
            }
        }
    }
    
    private func saveCurrency() {
        if let encoded = try? JSONEncoder().encode(selectedCurrency) {
            userDefaults.set(encoded, forKey: currencyKey)
        }
    }
    
    func formatPrice(_ amount: Double) -> String {
        return "\(selectedCurrency.symbol)\(String(format: "%.2f", amount))"
    }

    /// Returns suggested locale currency if a banner should be shown; nil otherwise.
    func checkLocaleChange() -> Currency? {
        guard !hasBeenManuallySet else { return nil }
        guard let savedCurrency = try? JSONDecoder().decode(Currency.self, from: userDefaults.data(forKey: currencyKey) ?? Data()) else { return nil }
        let localeCode = Locale.current.currency?.identifier ?? ""
        guard !localeCode.isEmpty, localeCode != savedCurrency.code else { return nil }
        let dismissedKey = dismissedLocaleChangeKey + localeCode
        guard !userDefaults.bool(forKey: dismissedKey) else { return nil }
        return Currency.currencies.first(where: { $0.code == localeCode })
    }

    func dismissLocaleChangeBanner(for currency: Currency) {
        userDefaults.set(true, forKey: dismissedLocaleChangeKey + currency.code)
    }

    func markAsManuallySet() {
        userDefaults.set(true, forKey: manuallySetCurrencyKey)
    }

    var hasBeenManuallySet: Bool {
        userDefaults.bool(forKey: manuallySetCurrencyKey)
    }
} 