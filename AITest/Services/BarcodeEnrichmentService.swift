import Foundation

// MARK: - EnrichedProduct
//
// Strongly-typed result returned by BarcodeEnrichmentService. All fields are
// normalised to Stoqly's domain (e.g. `category` is guaranteed to be one of
// `InventoryItem.predefinedCategories`, `uomSymbol` matches a `UOM.symbol`).

struct EnrichedProduct: Sendable {
    let name: String
    let description: String
    /// Exactly one of `InventoryItem.predefinedCategories`.
    let category: String
    /// Matches a `UOM.symbol` — defaults to `"pcs"`.
    let uomSymbol: String
}

/// One terminal outcome for a barcode enrichment attempt. The public shape is
/// deliberately analytics-ready so callers cannot collapse lookup misses,
/// network failures, and malformed provider responses back into a single nil.
struct BarcodeEnrichmentResult: Sendable {
    let product: EnrichedProduct?
    let outcome: String
    let provider: String
    let durationMs: Int
    let reason: String?
}

// MARK: - BarcodeEnrichmentService
//
// Tries free product databases in order (Open Food Facts → UPCItemDB),
// returns the first hit, or `nil` if neither finds the product.
//
// Contract:
//  - All errors are swallowed; the service never throws.
//  - Networking is best-effort: any failure (offline, timeout, malformed
//    payload) yields `nil`, never a crash.
//  - Callers populate the barcode field first; this service only fills
//    empty name/details. Single-scan lookup is free; bulk session is Pro.

// `Sendable` is safe here: the class has no stored properties, no mutable
// state — only stateless lookup methods. Required so the `shared` singleton
// can be referenced from arbitrary actor contexts (e.g. the `@MainActor`
// `enrichFromBarcode` in ItemFormViewModel) under Swift 6 strict concurrency.
final class BarcodeEnrichmentService: Sendable {

    static let shared = BarcodeEnrichmentService()
    private init() {}

    /// Compatibility wrapper for non-analytics callers and the existing live
    /// lookup tests. New barcode UI paths should use `enrichWithOutcome`.
    func enrich(barcode: String) async -> EnrichedProduct? {
        await enrichWithOutcome(barcode: barcode).product
    }

    /// Looks up a barcode and returns exactly one terminal result. Open Food
    /// Facts remains first; UPCItemDB is attempted as a fallback for every OFF
    /// miss or error so existing enrichment coverage is preserved.
    func enrichWithOutcome(barcode: String) async -> BarcodeEnrichmentResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let offResult = await lookupOpenFoodFacts(barcode: barcode)
        if case .found(let product) = offResult {
            return result(
                product: product,
                outcome: "found",
                provider: "off",
                startedAt: startedAt,
                reason: nil
            )
        }

        let upcResult = await lookupUPCItemDB(barcode: barcode)
        if case .found(let product) = upcResult {
            return result(
                product: product,
                outcome: "found",
                provider: "upcitemdb",
                startedAt: startedAt,
                reason: nil
            )
        }

        // Prefer the fallback provider's actionable error because it is the
        // last attempt the user waited for. If UPCItemDB merely missed, retain
        // OFF's richer failure classification; two clean misses are not_found.
        switch upcResult {
        case .networkError(let reason):
            return result(product: nil, outcome: "network_error", provider: "upcitemdb", startedAt: startedAt, reason: reason)
        case .parserError(let reason):
            return result(product: nil, outcome: "parser_error", provider: "upcitemdb", startedAt: startedAt, reason: reason)
        case .notFound:
            switch offResult {
            case .networkError(let reason):
                return result(product: nil, outcome: "network_error", provider: "off", startedAt: startedAt, reason: reason)
            case .parserError(let reason):
                return result(product: nil, outcome: "parser_error", provider: "off", startedAt: startedAt, reason: reason)
            case .notFound(let offReason):
                return result(product: nil, outcome: "not_found", provider: "off", startedAt: startedAt, reason: offReason)
            case .found:
                // Handled before the fallback lookup.
                return result(product: nil, outcome: "parser_error", provider: "off", startedAt: startedAt, reason: "Unexpected OFF result state")
            }
        case .found:
            // Handled above.
            return result(product: nil, outcome: "parser_error", provider: "upcitemdb", startedAt: startedAt, reason: "Unexpected UPCItemDB result state")
        }
    }

    private enum ProviderLookupResult {
        case found(EnrichedProduct)
        case notFound(reason: String)
        case networkError(reason: String)
        case parserError(reason: String)
    }

    private func result(
        product: EnrichedProduct?,
        outcome: String,
        provider: String,
        startedAt: CFAbsoluteTime,
        reason: String?
    ) -> BarcodeEnrichmentResult {
        BarcodeEnrichmentResult(
            product: product,
            outcome: outcome,
            provider: provider,
            durationMs: max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)),
            reason: reason
        )
    }

    // MARK: - Open Food Facts

    /// Open Food Facts is free, no API key, but coverage is heavily skewed to
    /// groceries / consumables. We try it first because it returns richer
    /// fields (categories_tags, quantity) that we can map cleanly.
    private func lookupOpenFoodFacts(barcode: String) async -> ProviderLookupResult {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            return .parserError(reason: "Invalid OFF URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            return .networkError(reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            return .parserError(reason: "OFF response was not HTTP")
        }
        if http.statusCode == 404 {
            return .notFound(reason: "OFF 404")
        }
        guard (200...299).contains(http.statusCode) else {
            return .networkError(reason: "OFF HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .parserError(reason: "OFF response JSON was malformed")
        }
        let status = json["status"] as? Int ?? -1
        if status == 0 {
            return .notFound(reason: "OFF 404")
        }
        guard status == 1, let product = json["product"] as? [String: Any] else {
            return .parserError(reason: "OFF product payload was missing")
        }

        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let genericName = (product["generic_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let brands      = (product["brands"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let quantity    = (product["quantity"] as? String) ?? ""
        let tags        = (product["categories_tags"] as? [String]) ?? []

        let name = productName.isEmpty ? genericName : productName
        guard !name.isEmpty else {
            return .parserError(reason: "OFF product name was empty")
        }

        let description: String
        if !genericName.isEmpty && genericName.lowercased() != name.lowercased() {
            description = genericName
        } else if !brands.isEmpty {
            description = brands
        } else {
            description = ""
        }

        return .found(
            EnrichedProduct(
                name: name,
                description: description,
                category: mapOFFCategory(tags: tags),
                uomSymbol: parseUOMSymbol(from: quantity)
            )
        )
    }

    // MARK: - UPCItemDB

    /// UPCItemDB free trial endpoint — no key required, ~100 requests/day per
    /// IP. Acceptable for MVP; revisit if usage scales.
    private func lookupUPCItemDB(barcode: String) async -> ProviderLookupResult {
        let urlString = "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)"
        guard let url = URL(string: urlString) else {
            return .parserError(reason: "Invalid UPCItemDB URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            return .networkError(reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            return .parserError(reason: "UPCItemDB response was not HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            return .networkError(reason: "UPCItemDB HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .parserError(reason: "UPCItemDB response JSON was malformed")
        }
        let code = json["code"] as? String ?? "nil"
        let total = json["total"] as? Int ?? 0
        guard code == "OK", total > 0 else {
            return .notFound(reason: "UPCItemDB \(code)")
        }
        guard let items = json["items"] as? [[String: Any]],
              let first = items.first else {
            return .parserError(reason: "UPCItemDB item payload was missing")
        }

        let title    = (first["title"]       as? String) ?? ""
        let desc     = (first["description"] as? String) ?? ""
        let category = (first["category"]    as? String) ?? ""

        guard !title.isEmpty else {
            return .parserError(reason: "UPCItemDB title was empty")
        }

        return .found(
            EnrichedProduct(
                name: title,
                description: String(desc.prefix(200)),
                category: mapUPCCategory(category: category),
                uomSymbol: "pcs"
            )
        )
    }

    // MARK: - Category mapping

    /// Ordered keyword groups. Each tuple is (substrings, Stoqly category).
    /// First match wins, so put the most specific groups before the more
    /// generic ones (e.g. "medication" before any "food" substring overlap).
    private static let categoryKeywordGroups: [(keywords: [String], category: String)] = [
        // Pharmaceutical first — "medicine", "drug" can otherwise drift into
        // Health & Beauty via supplements.
        (["medication", "pharmaceutical", "drug", "medicine"],
         "Pharmaceutical"),

        (["beverage", "drink", "soda", "water", "juice",
          "dairy", "cheese", "yogurt", "milk",
          "bread", "cereal", "snack", "chocolate", "biscuit",
          "meat", "fish", "seafood",
          "fruit", "vegetable", "condiment", "sauce", "spice", "food"],
         "Food & Beverage"),

        (["cleaning", "detergent", "soap", "hygiene", "toiletry", "paper-product"],
         "Cleaning & Hygiene"),

        (["electronic", "computer", "phone", "cable"],
         "Electronics & Equipment"),

        (["clothing", "apparel", "shoe", "fashion"],
         "Clothing & Apparel"),

        (["beauty", "cosmetic", "makeup", "skincare", "haircare",
          "vitamin", "supplement", "health"],
         "Health & Beauty"),

        (["office-suppli", "stationery"],
         "Stationery & Office"),

        (["packaging", "container"],
         "Packaging & Supplies"),
    ]

    /// Open Food Facts returns `categories_tags` as `["en:beverages", ...]`.
    /// Iterate the tags in order and return the first Stoqly category that
    /// matches any substring keyword (case-insensitive).
    private func mapOFFCategory(tags: [String]) -> String {
        for tag in tags {
            let lowered = tag.lowercased()
            for group in Self.categoryKeywordGroups {
                if group.keywords.contains(where: { lowered.contains($0) }) {
                    return group.category
                }
            }
        }
        return "Uncategorised"
    }

    /// UPCItemDB returns `category` as a single free-form string. Same
    /// keyword groups, single haystack.
    private func mapUPCCategory(category: String) -> String {
        let lowered = category.lowercased()
        guard !lowered.isEmpty else { return "Uncategorised" }
        for group in Self.categoryKeywordGroups {
            if group.keywords.contains(where: { lowered.contains($0) }) {
                return group.category
            }
        }
        return "Uncategorised"
    }

    // MARK: - UOM parsing

    /// Parse the first unit token from an Open Food Facts `quantity` string
    /// (e.g. `"500 ml"`, `"1 kg"`, `"6 x 330ml"`). Returns one of the symbols
    /// matching a standard `UOM.symbol`, defaulting to `"pcs"`.
    private func parseUOMSymbol(from quantity: String) -> String {
        let trimmed = quantity.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "pcs" }

        // Multi-pack indicators ("6 x 330ml", "2x") → treat as countable.
        let lowered = trimmed.lowercased()
        if lowered.contains(" x ") || lowered.contains("x ") || lowered.contains(" x") {
            return "pcs"
        }

        // Extract the first alphabetic run that follows the leading number
        // (skipping digits, dots, commas, and whitespace).
        var seenDigit = false
        var unitChars: [Character] = []
        for ch in trimmed {
            if ch.isNumber || ch == "." || ch == "," {
                seenDigit = true
                continue
            }
            if ch.isWhitespace {
                if !unitChars.isEmpty { break }
                continue
            }
            if ch.isLetter {
                // Only start collecting letters after we've passed the number.
                if seenDigit || !unitChars.isEmpty {
                    unitChars.append(ch)
                } else {
                    // Letters before any digit — bail to default.
                    return "pcs"
                }
            } else {
                if !unitChars.isEmpty { break }
            }
        }

        let token = String(unitChars).lowercased()
        guard !token.isEmpty else { return "pcs" }

        switch token {
        case "ml", "milliliter", "millilitre", "milliliters", "millilitres":
            return "mL"
        case "l", "liter", "litre", "liters", "litres":
            return "L"
        case "g", "gram", "gramme", "grams", "grammes":
            return "g"
        case "kg", "kilogram", "kilogramme", "kilograms", "kilogrammes":
            return "kg"
        case "m", "meter", "metre", "meters", "metres":
            return "m"
        case "cm", "centimeter", "centimetre", "centimeters", "centimetres":
            return "cm"
        default:
            return "pcs"
        }
    }
}
