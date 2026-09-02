import Foundation

/// Versioned owner profile used to tailor Stoqly and, only with explicit consent,
/// let the Stoqly team contact the business by phone or WhatsApp.
struct BusinessProfile: Equatable {
    static let currentSchemaVersion = 1
    static let consentVersion = "business-contact-2026-09-01-v1"

    let schemaVersion: Int
    let businessName: String?
    let businessType: BusinessType
    let otherBusinessType: String?
    /// ISO 3166-1 alpha-2 region code, e.g. "IN". Stored as a code, never a
    /// display name, so the value survives a language change.
    let country: String
    /// Indian State / UT for `country == "IN"`; free text elsewhere.
    let state: String
    let city: String?
    let phoneNumber: String?
    let contactConsent: Bool
    let completedAt: Date?

    var displayBusinessType: String {
        if businessType == .other, let otherBusinessType, !otherBusinessType.isEmpty {
            return otherBusinessType
        }
        return businessType.displayName
    }
}

enum BusinessType: String, CaseIterable, Identifiable {
    case supermarketGrocery = "supermarket_grocery"
    case pharmacy = "pharmacy"
    case automobile = "automobile"
    case electronics = "electronics"
    case retail = "retail"
    case wholesaleDistribution = "wholesale_distribution"
    case restaurantCafe = "restaurant_cafe"
    case manufacturing = "manufacturing"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .supermarketGrocery: return "Supermarket / Grocery"
        case .pharmacy: return "Pharmacy / Medical Shop"
        case .automobile: return "Automobile / Auto Parts"
        case .electronics: return "Electronics / Electrical"
        case .retail: return "Retail / General Store"
        case .wholesaleDistribution: return "Wholesale / Distribution"
        case .restaurantCafe: return "Restaurant / Cafe"
        case .manufacturing: return "Manufacturing"
        case .other: return "Other"
        }
    }

    /// Short label used on the selectable tiles. Kept to one or two words so
    /// Tamil / Malayalam / Hindi translations do not clip inside the grid.
    var shortName: String {
        switch self {
        case .supermarketGrocery: return "Grocery"
        case .pharmacy: return "Pharmacy"
        case .automobile: return "Auto Parts"
        case .electronics: return "Electronics"
        case .retail: return "General Store"
        case .wholesaleDistribution: return "Wholesale"
        case .restaurantCafe: return "Restaurant"
        case .manufacturing: return "Manufacturing"
        case .other: return "Other"
        }
    }

    /// `Text(String)` uses the non-localizing overload, and SwiftUI's automatic
    /// lookup ignores the in-app language override, so both labels resolve
    /// through `L(...)` like the rest of the app.
    var localizedDisplayName: String {
        L("businessType.\(rawValue)", displayName)
    }

    var localizedShortName: String {
        L("businessType.short.\(rawValue)", shortName)
    }

    var iconName: String {
        switch self {
        case .supermarketGrocery: return "cart.fill"
        case .pharmacy: return "cross.case.fill"
        case .automobile: return "wrench.and.screwdriver.fill"
        case .electronics: return "bolt.fill"
        case .retail: return "storefront.fill"
        case .wholesaleDistribution: return "shippingbox.fill"
        case .restaurantCafe: return "fork.knife"
        case .manufacturing: return "gearshape.2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum BusinessProfileOptions {
    static let indiaRegionCode = "IN"

    /// ISO alpha-2 regions only — `isoRegions` also contains numeric groupings
    /// like "001" (World) and "150" (Europe), which are not countries.
    static let countryCodes: [String] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 }
        .sorted()

    /// Main-actor isolated because it resolves through the in-app language
    /// override; all callers are SwiftUI views, which are already main-actor.
    @MainActor
    static func countryName(for code: String) -> String {
        LocalizationManager.shared.effectiveLocale()
            .localizedString(forRegionCode: code) ?? code
    }

    /// Device region when we can map it to a known country, else India — the
    /// overwhelmingly likely answer for this app.
    static func defaultCountryCode() -> String {
        if let region = Locale.current.region?.identifier, countryCodes.contains(region) {
            return region
        }
        return indiaRegionCode
    }

    /// Curated subdivision lists, keyed by ISO 3166-1 alpha-2 country code.
    ///
    /// Only countries where Stoqly actually has users are listed — there is no
    /// value in shipping 200 lists nobody opens. A country that is absent simply
    /// falls back to a free-text field, and even a country that IS present keeps
    /// a "use what I typed" escape hatch in the picker, so an outdated or
    /// incomplete list here can never lock anyone out of the required prompt.
    ///
    /// Names are official English/romanized forms, matching the Indian list's
    /// convention. Add a country by adding a row — nothing else needs to change.
    static let subdivisionsByCountry: [String: [String]] = [
        "IN": indianStatesAndUnionTerritories,
        "US": unitedStatesStates,
        "NG": nigerianStates,
        "ID": indonesianProvinces,
        "EG": egyptianGovernorates,
        "MX": mexicanStates,
        "DE": germanStates,
        "IE": irishCounties,
        "JM": jamaicanParishes,
        "DZ": algerianProvinces
    ]

    /// nil means "no curated list — use a free-text field".
    static func subdivisions(for country: String) -> [String]? {
        subdivisionsByCountry[country]
    }

    static let unitedStatesStates = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
        "Connecticut", "Delaware", "District of Columbia", "Florida", "Georgia",
        "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
        "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
        "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
        "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
        "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont",
        "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
    ]

    static let nigerianStates = [
        "Abia", "Adamawa", "Akwa Ibom", "Anambra", "Bauchi", "Bayelsa", "Benue",
        "Borno", "Cross River", "Delta", "Ebonyi", "Edo", "Ekiti", "Enugu",
        "Federal Capital Territory", "Gombe", "Imo", "Jigawa", "Kaduna", "Kano",
        "Katsina", "Kebbi", "Kogi", "Kwara", "Lagos", "Nasarawa", "Niger", "Ogun",
        "Ondo", "Osun", "Oyo", "Plateau", "Rivers", "Sokoto", "Taraba", "Yobe",
        "Zamfara"
    ]

    static let indonesianProvinces = [
        "Aceh", "Bali", "Bangka Belitung Islands", "Banten", "Bengkulu",
        "Central Java", "Central Kalimantan", "Central Papua", "Central Sulawesi",
        "East Java", "East Kalimantan", "East Nusa Tenggara", "Gorontalo",
        "Highland Papua", "Jakarta", "Jambi", "Lampung", "Maluku",
        "North Kalimantan", "North Maluku", "North Sulawesi", "North Sumatra",
        "Papua", "Riau", "Riau Islands", "South Kalimantan", "South Papua",
        "South Sulawesi", "South Sumatra", "Southeast Sulawesi", "Southwest Papua",
        "West Java", "West Kalimantan", "West Nusa Tenggara", "West Papua",
        "West Sulawesi", "West Sumatra", "Yogyakarta"
    ]

    static let egyptianGovernorates = [
        "Alexandria", "Aswan", "Asyut", "Beheira", "Beni Suef", "Cairo",
        "Dakahlia", "Damietta", "Faiyum", "Gharbia", "Giza", "Ismailia",
        "Kafr El Sheikh", "Luxor", "Matrouh", "Minya", "Monufia", "New Valley",
        "North Sinai", "Port Said", "Qalyubia", "Qena", "Red Sea", "Sharqia",
        "Sohag", "South Sinai", "Suez"
    ]

    static let mexicanStates = [
        "Aguascalientes", "Baja California", "Baja California Sur", "Campeche",
        "Chiapas", "Chihuahua", "Coahuila", "Colima", "Durango", "Guanajuato",
        "Guerrero", "Hidalgo", "Jalisco", "Mexico City", "Michoacán", "Morelos",
        "Nayarit", "Nuevo León", "Oaxaca", "Puebla", "Querétaro", "Quintana Roo",
        "San Luis Potosí", "Sinaloa", "Sonora", "State of México", "Tabasco",
        "Tamaulipas", "Tlaxcala", "Veracruz", "Yucatán", "Zacatecas"
    ]

    static let germanStates = [
        "Baden-Württemberg", "Bavaria", "Berlin", "Brandenburg", "Bremen",
        "Hamburg", "Hesse", "Lower Saxony", "Mecklenburg-Vorpommern",
        "North Rhine-Westphalia", "Rhineland-Palatinate", "Saarland", "Saxony",
        "Saxony-Anhalt", "Schleswig-Holstein", "Thuringia"
    ]

    static let irishCounties = [
        "Carlow", "Cavan", "Clare", "Cork", "Donegal", "Dublin", "Galway",
        "Kerry", "Kildare", "Kilkenny", "Laois", "Leitrim", "Limerick",
        "Longford", "Louth", "Mayo", "Meath", "Monaghan", "Offaly", "Roscommon",
        "Sligo", "Tipperary", "Waterford", "Westmeath", "Wexford", "Wicklow"
    ]

    static let jamaicanParishes = [
        "Clarendon", "Hanover", "Kingston", "Manchester", "Portland",
        "Saint Andrew", "Saint Ann", "Saint Catherine", "Saint Elizabeth",
        "Saint James", "Saint Mary", "Saint Thomas", "Trelawny", "Westmoreland"
    ]

    static let algerianProvinces = [
        "Adrar", "Aïn Defla", "Aïn Témouchent", "Algiers", "Annaba", "Batna",
        "Béchar", "Béjaïa", "Beni Abbès", "Biskra", "Blida", "Bordj Baji Mokhtar",
        "Bordj Bou Arréridj", "Bouira", "Boumerdès", "Chlef", "Constantine",
        "Djanet", "Djelfa", "El Bayadh", "El Meghaier", "El Menia", "El Oued",
        "El Tarf", "Ghardaïa", "Guelma", "Illizi", "In Guezzam", "In Salah",
        "Jijel", "Khenchela", "Laghouat", "M'Sila", "Mascara", "Médéa", "Mila",
        "Mostaganem", "Naâma", "Oran", "Ouargla", "Ouled Djellal",
        "Oum El Bouaghi", "Relizane", "Saïda", "Sétif", "Sidi Bel Abbès",
        "Skikda", "Souk Ahras", "Tamanrasset", "Tébessa", "Tiaret", "Timimoun",
        "Tindouf", "Tipaza", "Tissemsilt", "Tizi Ouzou", "Tlemcen", "Touggourt"
    ]

    static let indianStatesAndUnionTerritories = [
        "Andaman and Nicobar Islands",
        "Andhra Pradesh",
        "Arunachal Pradesh",
        "Assam",
        "Bihar",
        "Chandigarh",
        "Chhattisgarh",
        "Dadra and Nagar Haveli and Daman and Diu",
        "Delhi",
        "Goa",
        "Gujarat",
        "Haryana",
        "Himachal Pradesh",
        "Jammu and Kashmir",
        "Jharkhand",
        "Karnataka",
        "Kerala",
        "Ladakh",
        "Lakshadweep",
        "Madhya Pradesh",
        "Maharashtra",
        "Manipur",
        "Meghalaya",
        "Mizoram",
        "Nagaland",
        "Odisha",
        "Puducherry",
        "Punjab",
        "Rajasthan",
        "Sikkim",
        "Tamil Nadu",
        "Telangana",
        "Tripura",
        "Uttar Pradesh",
        "Uttarakhand",
        "West Bengal"
    ]
}

enum BusinessProfileValidation {
    static let maximumOtherBusinessTypeLength = 80
    static let maximumStateLength = 60
    static let maximumCityLength = 60
    static let maximumBusinessNameLength = 80

    /// Business name is optional free text. Trimmed, capped, and normalized to
    /// nil when blank so an empty string is never written to Firestore.
    static func normalizedBusinessName(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumBusinessNameLength))
    }

    /// City is optional free text. It is trimmed and capped, and an empty value
    /// normalizes to nil so we never write a blank string to Firestore.
    static func normalizedCity(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumCityLength))
    }

    static func normalizedPhoneNumber(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.first == "+" else { return nil }

        let asciiDigits = CharacterSet(charactersIn: "0123456789")
        let allowedFormatting = CharacterSet(charactersIn: " -().")
        let remainder = String(trimmed.dropFirst())
        guard remainder.unicodeScalars.allSatisfy({
            asciiDigits.contains($0) || allowedFormatting.contains($0)
        }) else { return nil }

        let digits = remainder.unicodeScalars
            .filter { asciiDigits.contains($0) }
            .map(String.init)
            .joined()
        guard (7...15).contains(digits.count) else { return nil }
        return "+" + digits
    }

    /// Canonical, low-cardinality city label for analytics ONLY. Firestore keeps
    /// exactly what the owner typed; this collapses case and spacing, folds a few
    /// well-known Indian alternate names onto one spelling, and refuses anything
    /// that looks like it is not a city name.
    ///
    /// Returns nil when the value contains a digit — a free-text box will
    /// occasionally receive a phone number or a full street address, and neither
    /// belongs in a third-party analytics tool.
    static func analyticsCity(from input: String) -> String? {
        guard let trimmed = normalizedCity(from: input) else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else {
            return nil
        }

        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count <= maximumAnalyticsCityLength else { return nil }

        let folded = collapsed.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        if let canonical = cityAliases[folded] { return canonical }

        return collapsed
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    static let maximumAnalyticsCityLength = 40

    /// Only the alternate spellings that actually matter for Stoqly's region
    /// reporting. Keys are lowercased and diacritic-folded.
    private static let cityAliases: [String: String] = [
        "cochin": "Kochi",           "kochi": "Kochi",           "ernakulam": "Kochi",
        "calicut": "Kozhikode",      "kozhikode": "Kozhikode",
        "trichur": "Thrissur",       "thrissur": "Thrissur",
        "trivandrum": "Thiruvananthapuram", "thiruvananthapuram": "Thiruvananthapuram",
        "madras": "Chennai",         "chennai": "Chennai",
        "kovai": "Coimbatore",       "coimbatore": "Coimbatore",
        "trichy": "Tiruchirappalli", "tiruchirappalli": "Tiruchirappalli",
        "bangalore": "Bengaluru",    "bengaluru": "Bengaluru",
        "bombay": "Mumbai",          "mumbai": "Mumbai",
        "poona": "Pune",             "pune": "Pune",
        "calcutta": "Kolkata",       "kolkata": "Kolkata",
        "pondicherry": "Puducherry", "puducherry": "Puducherry",
        "baroda": "Vadodara",        "vadodara": "Vadodara",
        "allahabad": "Prayagraj",    "prayagraj": "Prayagraj",
        "gurgaon": "Gurugram",       "gurugram": "Gurugram"
    ]

    /// Any non-empty subdivision is accepted, for every country including India.
    ///
    /// The curated lists in `BusinessProfileOptions` are a convenience that
    /// makes the common path one tap and keeps the data clean — they are
    /// deliberately NOT a gate. A required, non-dismissible prompt must never be
    /// unsatisfiable, and hard-gating on a hand-maintained list would recreate
    /// exactly that failure the day a country adds a subdivision.
    static func isValidState(_ state: String, country: String) -> Bool {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumStateLength
    }

    static func isValid(
        businessType: BusinessType?,
        otherBusinessType: String,
        country: String,
        state: String,
        phoneInput: String,
        contactConsent: Bool
    ) -> Bool {
        guard let businessType,
              BusinessProfileOptions.countryCodes.contains(country),
              isValidState(state, country: country) else {
            return false
        }

        if businessType == .other {
            let customType = otherBusinessType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !customType.isEmpty,
                  customType.count <= maximumOtherBusinessTypeLength else { return false }
        }

        let trimmedPhone = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPhone.isEmpty {
            guard normalizedPhoneNumber(from: trimmedPhone) != nil, contactConsent else {
                return false
            }
        }
        return true
    }
}
