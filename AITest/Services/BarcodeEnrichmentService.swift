import Foundation

// MARK: - EnrichedProduct
//
// Strongly-typed result returned by BarcodeEnrichmentService. All fields are
// normalised to Stoqly's domain (e.g. `category` is guaranteed to be one of
// `InventoryItem.predefinedCategories`, `uomSymbol` matches a `UOM.symbol`).

struct EnrichedProduct {
    let name: String
    let description: String
    /// Exactly one of `InventoryItem.predefinedCategories`.
    let category: String
    /// Matches a `UOM.symbol` — defaults to `"pcs"`.
    let uomSymbol: String
}

// MARK: - BarcodeEnrichmentService
//
// Phase 3 — Pro-only smart barcode lookup. Tries free product databases in
// order (Open Food Facts → UPCItemDB), returns the first hit, or `nil` if
// neither finds the product.
//
// Contract:
//  - All errors are swallowed; the service never throws.
//  - Networking is best-effort: any failure (offline, timeout, malformed
//    payload) yields `nil`, never a crash.
//  - Caller is responsible for gating on `SubscriptionManager.shared.isPro`.

// `Sendable` is safe here: the class has no stored properties, no mutable
// state — only stateless lookup methods. Required so the `shared` singleton
// can be referenced from arbitrary actor contexts (e.g. the `@MainActor`
// `enrichFromBarcode` in ItemFormViewModel) under Swift 6 strict concurrency.
final class BarcodeEnrichmentService: Sendable {

    static let shared = BarcodeEnrichmentService()
    private init() {}

    /// Look up a barcode against external product databases. Returns `nil`
    /// when no source recognises the code or every source errors out.
    func enrich(barcode: String) async -> EnrichedProduct? {
        if let result = await lookupOpenFoodFacts(barcode: barcode) {
            return result
        }
        if let result = await lookupUPCItemDB(barcode: barcode) {
            return result
        }
        return nil
    }

    // MARK: - Open Food Facts

    /// Open Food Facts is free, no API key, but coverage is heavily skewed to
    /// groceries / consumables. We try it first because it returns richer
    /// fields (categories_tags, quantity) that we can map cleanly.
    private func lookupOpenFoodFacts(barcode: String) async -> EnrichedProduct? {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let status = json["status"] as? Int ?? -1
        guard status == 1, let product = json["product"] as? [String: Any] else { return nil }

        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let genericName = (product["generic_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let brands      = (product["brands"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let quantity    = (product["quantity"] as? String) ?? ""
        let tags        = (product["categories_tags"] as? [String]) ?? []

        let name = productName.isEmpty ? genericName : productName
        guard !name.isEmpty else { return nil }

        let description: String
        if !genericName.isEmpty && genericName.lowercased() != name.lowercased() {
            description = genericName
        } else if !brands.isEmpty {
            description = brands
        } else {
            description = ""
        }

        return EnrichedProduct(
            name: name,
            description: description,
            category: mapOFFCategory(tags: tags),
            uomSymbol: parseUOMSymbol(from: quantity)
        )
    }

    // MARK: - UPCItemDB

    /// UPCItemDB free trial endpoint — no key required, ~100 requests/day per
    /// IP. Acceptable for MVP; revisit if usage scales.
    private func lookupUPCItemDB(barcode: String) async -> EnrichedProduct? {
        let urlString = "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)"
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let code = json["code"] as? String ?? "nil"
        let total = json["total"] as? Int ?? 0
        guard code == "OK", total > 0,
              let items = json["items"] as? [[String: Any]],
              let first = items.first else { return nil }

        let title    = (first["title"]       as? String) ?? ""
        let desc     = (first["description"] as? String) ?? ""
        let category = (first["category"]    as? String) ?? ""

        guard !title.isEmpty else { return nil }

        return EnrichedProduct(
            name: title,
            description: String(desc.prefix(200)),
            category: mapUPCCategory(category: category),
            uomSymbol: "pcs"
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
