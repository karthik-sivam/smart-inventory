import Foundation
import UIKit

// MARK: - ParsedInventoryItem
//
// Structured item returned by any AI inventory parse (voice, image, paper).
// All fields are optional — the AI fills what it can; the user confirms the rest.

struct ParsedInventoryItem: Identifiable {
    let id = UUID()
    var name: String
    var quantity: Double?
    var unitSymbol: String?        // e.g. "kg", "pcs", "L"
    var category: String?          // one of InventoryItem.predefinedCategories
    var notes: String?
    var confidence: Double         // 0.0–1.0 from AI
    var fillPercent: Double?       // liquid fill level 0–100
    var remainingVolume: String?   // e.g. "~325ml"
    var unitCost: Double?
    var sellingPrice: Double?
    var expiryDate: Date?
    var sku: String?
    var barcode: String?
    var minQuantity: Double?
}

// MARK: - AIInventoryError

enum AIInventoryError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case noItemsFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key not configured. Please add it in Settings → AI Features."
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .invalidResponse:
            return "Couldn't understand the AI response. Please try again."
        case .noItemsFound:
            return "No inventory items were detected. Please try again with clearer input."
        }
    }
}

// MARK: - AIInventoryService

/// Wraps the Anthropic Messages API for three inventory-input modes:
///   1. `parseVoiceTranscript` — turn a speech transcript into structured items
///   2. `identifyProduct`      — identify a single product from a photo
///   3. `parseInventorySheet`  — OCR a handwritten/printed inventory list
///
/// All methods are async and throw `AIInventoryError`. The caller is responsible
/// for showing the review UI before committing results to SwiftData.

final class AIInventoryService {
    // nonisolated(unsafe): lazily-initialised let constant, never mutated after first access.
    nonisolated(unsafe) static let shared = AIInventoryService()
    private init() {}

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model    = "claude-haiku-4-5-20251001"

    private static let optionalItemFieldsPrompt = """
    Optional fields — include ONLY if clearly stated; otherwise omit or set null (do NOT guess):
    - "unitCost", "sellingPrice", "minQuantity": numbers
    - "expiryDate": ISO date string YYYY-MM-DD when a clear expiry is mentioned
    - "sku", "barcode": strings
    - "notes": extra detail not captured elsewhere
    """

    private static let machineFieldsEnglishRule = """
    Keep "unit", "quantity", "category", "fillPercent", "remainingVolume" and all numeric/machine fields in standard ENGLISH/numeric form (pcs, kg, g, L, mL, btl, can). Only the "name" field follows the user's spoken/written language.
    """

    private static func appLanguageNameRule(for lang: String) -> String {
        """
        LANGUAGE: The app is set to language code '\(lang)'. This affects ONLY the "name" field: for GENERIC/unbranded items, write the name in that language's native script; keep brand names and on-label text EXACTLY as printed/written. \(machineFieldsEnglishRule)
        """
    }

    private static func todayISO() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    private static var expiryDateAnchorPrompt: String {
        """
        Today's date is \(todayISO()) (the device's local date).
        Expiry rules:
        - Resolve relative expiry expressions ("in 5 days", "expires next week", "end of month", "in 2 months") to an absolute calendar date in YYYY-MM-DD, computed from today's date above.
        - A future expiry MUST be a date AFTER today. Never output a past date unless the user explicitly states the item is already expired.
        - If no expiry is mentioned, return null. Do not invent one.
        """
    }

    // MARK: - Voice transcript → items

    /// Takes the raw text from SFSpeechRecognizer and returns a list of items
    /// the user mentioned. Handles natural speech like "5 kg of flour, 2 boxes
    /// of sugar, and we're out of salt".
    func parseVoiceTranscript(
        _ transcript: String,
        inventoryHints: [String] = [],
        appLanguageCode: String? = nil
    ) async throws -> [ParsedInventoryItem] {
        let inventoryHint = inventoryHints.prefix(50).joined(separator: ", ")
        let contextPrefix = inventoryHint.isEmpty
            ? ""
            : "The user's inventory includes: \(inventoryHint). Use these as spelling hints when matching spoken product names.\n\n"

        let quantityHints = Self.quantityExpressionHints(for: appLanguageCode)

        let promptBody = """
        \(Self.expiryDateAnchorPrompt)

        \(contextPrefix)You are an inventory assistant. The user has dictated an inventory count verbally.

        Transcript: "\(transcript)"

        Extract each inventory item mentioned. Return a JSON array only, no explanation.

        Format:
        [
          {
            "name": "item name",
            "quantity": 5.0,
            "unit": "kg",
            "category": "Food & Beverage",
            "confidence": 0.95,
            "unitCost": 20.0,
            "sellingPrice": 30.0,
            "expiryDate": "2026-09-01",
            "sku": null,
            "barcode": null,
            "minQuantity": null,
            "notes": null
          }
        ]

        Rules:
        - "name" must be a clean product name (strip quantities/units/filler, e.g. "Flour", not "5 kg of flour")
        - KEEP "name" in the SAME language and script the user spoke it in. Do NOT translate or transliterate the product name into English — if the user said a Tamil name, return it in Tamil script; Hindi → Devanagari, etc. The product name is the user's data, not something to localise.
        - EXCEPTION: if a spoken item clearly matches one already in the user's inventory list above, return that existing item's EXACT stored name (even if it's in another language) so it updates that item instead of creating a duplicate.
        - "quantity" is a number, null if not mentioned
        - "unit" use standard abbreviations: pcs, kg, g, L, mL, m, cm. null if unclear
        - "category" must be one of: Food & Beverage, Cleaning & Hygiene, Packaging & Supplies, Electronics & Equipment, Clothing & Apparel, Health & Beauty, Pharmaceutical, Raw Materials, Spare Parts, Stationery & Office, Uncategorised
        - "confidence" 0.0-1.0 how confident you are this is a real inventory item
        - Skip filler words and conversation
        - Return [] if nothing recognisable was said
        \(Self.optionalItemFieldsPrompt)
        \(Self.machineFieldsEnglishRule)
        \(quantityHints)
        """

        var prompt = promptBody
        if let lang = appLanguageCode, lang != "en", !lang.isEmpty {
            prompt += "\n\n\(Self.appLanguageNameRule(for: lang))"
        }

        return try await callClaude(textPrompt: prompt, imageData: nil)
    }

    /// Language-specific quantity expression hints for voice extraction (S14-B6).
    private static func quantityExpressionHints(for appLanguageCode: String?) -> String {
        let code = appLanguageCode?.split(separator: "-").first.map(String.init) ?? "en"
        switch code {
        case "hi":
            return "- Understand Hindi quantity expressions: 'ek dozen' = 12, 'aadha kilo' / 'aadha kg' = 0.5 kg, 'pauna kilo' = 0.75 kg, 'sava kilo' = 1.25 kg, 'do kilo' = 2 kg. Also Indian English: 'two and a half kilo' = 2.5 kg, 'half litre' = 0.5 L."
        case "ta":
            return "- Understand Tamil quantity expressions: 'arai kilo' = 0.5 kg, 'oru kilo' = 1 kg, 'rendu kilo' = 2 kg, 'oru dozen' = 12 units."
        case "te":
            return "- Understand Telugu quantity expressions: 'okati kilo' = 1 kg, 'rendu kilo' = 2 kg, 'half kilo' = 0.5 kg, 'okati dozen' = 12 units."
        case "kn":
            return "- Understand Kannada quantity expressions: 'ondu kilo' = 1 kg, 'eradu kilo' = 2 kg, 'half kilo' = 0.5 kg."
        case "ml":
            return "- Understand Malayalam quantity expressions: 'onnu kilo' = 1 kg, 'randu kilo' = 2 kg, 'half kilo' = 0.5 kg."
        case "ar":
            return "- Understand Arabic quantity expressions: 'نصف كيلو' = 0.5 kg, 'كilo واحد' = 1 kg, 'دزينة' = 12 units."
        case "es":
            return "- Understand Spanish: 'medio kilo' = 0.5 kg, 'un kilo y medio' = 1.5 kg, 'una docena' = 12."
        case "fr":
            return "- Understand French: 'demi kilo' = 0.5 kg, 'un kilo et demi' = 1.5 kg, 'une douzaine' = 12."
        case "de":
            return "- Understand German: 'ein halbes Kilo' = 0.5 kg, 'anderthalb Kilo' = 1.5 kg, 'ein Dutzend' = 12."
        case "ja":
            return "- Understand Japanese: '半キロ' = 0.5 kg, '1キロ' = 1 kg, '1ダース' = 12."
        default:
            return "- Understand Indian English quantity expressions: 'two and a half kilo' = 2.5 kg, 'one dozen' = 12 units, 'half litre' = 0.5 L, 'quarter kg' = 0.25 kg. Extract item name, quantity as a number, and unit separately."
        }
    }

    // MARK: - Product photo → item

    /// Takes a photo of a product or shelf and returns the identified product
    /// WITH a counted quantity based on what is visible in the frame.
    func identifyProduct(imageData: Data, fluidMode: Bool = false, appLanguageCode: String? = nil) async throws -> [ParsedInventoryItem] {
        var prompt = """
        \(Self.expiryDateAnchorPrompt)

        You are an inventory counting assistant. Analyse the image and identify ALL distinct products visible.
        For each product:
        - Count the number of physically separate units visible (e.g. 6 cans = quantity 6, not 1).
        - If units are partially hidden or stacked, estimate the total visible count.
        - If the product is a liquid/fluid in a container AND the fill level is visible, estimate the fill percentage (e.g. 65%) and, if the label shows total volume (e.g. 500ml), calculate the remaining volume (e.g. ~325ml).
        - If this is a single liquid container and fluid mode is active, prioritise fill-level estimation over unit count.
        Return JSON array: [{"name", "quantity", "unit", "fillPercent" (if liquid), "remainingVolume" (if calculable), "category", "confidence", "unitCost", "sellingPrice", "expiryDate", "sku", "barcode", "minQuantity", "notes"}]

        Counting rules:
        - Count every individual unit you can see (bottles, boxes, cans, bags, etc.)
        - If items are arranged in rows and columns, count all cells visible (rows × columns),
          including partially visible units at the edges.
        - If items are stacked and some are hidden behind others, estimate the total:
          count the front row/layer and multiply by how many layers deep you can infer.
        - If it is clearly a single item, quantity = 1.
        - Never leave quantity null — always give your best estimate.

        Rules:
        - "name": for BRANDED/packaged goods, use the name printed on the label/packaging EXACTLY as shown (e.g. "Heinz Tomato Ketchup 500ml") — never translate a brand or on-label text
        - "quantity": counted or estimated number of units — never null
        - "unit": infer from product type (bottles/cans/boxes → "pcs", loose flour → "kg", liquids → "L" or "mL")
        - "fillPercent": 0–100 for liquids when fill level is visible, null otherwise
        - "remainingVolume": estimated remaining volume string (e.g. "~325ml") when calculable
        - "category": one of: Food & Beverage, Cleaning & Hygiene, Packaging & Supplies,
          Electronics & Equipment, Clothing & Apparel, Health & Beauty, Pharmaceutical,
          Raw Materials, Spare Parts, Stationery & Office, Uncategorised
        - "confidence": 0.0–1.0 — lower when counting is uncertain due to occlusion or blur
        - Return [] only if the image is completely unidentifiable
        \(Self.optionalItemFieldsPrompt)
        \(Self.machineFieldsEnglishRule)
        """

        if let lang = appLanguageCode, lang != "en", !lang.isEmpty {
            prompt += "\n\n\(Self.appLanguageNameRule(for: lang))"
        }

        if fluidMode {
            prompt += "\n\nFLUID MODE: The captured image contains a liquid container. Prioritise estimating fill percentage and remaining volume over counting units."
        }

        return try await callClaude(textPrompt: prompt, imageData: imageData)
    }

    // MARK: - Help Centre AI chat

    /// Answers a user question about Stoqly using the Claude API.
    /// Returns a plain-text answer string. Throws AIInventoryError on failure.
    func askHelpQuestion(_ question: String) async throws -> String {
        let systemPrompt = """
        You are the in-app support assistant for Stoqly, an AI-powered inventory management \
        app for small businesses (shops, restaurants, cafes, warehouses).

        You know everything about Stoqly. Here is the complete feature set:

        CORE FEATURES:
        - Storages: locations in the business (shelf, room, freezer, section). Users create \
          storages to organise inventory by location. Free plan: up to 5 storages.
        - Items: products tracked within a storage. Each item has name, quantity, unit, \
          category, barcode, cost price, selling price, min quantity / reorder percentage. \
          Free plan: up to 50 items per storage.
        - Quick Count: fast quantity update — set to exact value or adjust by +/-.
        - Activity Feed: full history of every count, sale, movement, and import event.
        - Barcode Scanner: scan any barcode to add or find an item.
        - Dashboard: KPI cards (total items, storages, low stock, total value), Smart Insights \
          (profit margin, cost trends, data-health nudges), sales and movement charts.
        - Reorder List: shows all items below their minimum level, grouped by supplier \
          with a one-tap email to supplier.
        - Export: CSV and PDF export of full inventory.
        - Push Notifications: low-stock alerts and daily summary.
        - Offline Support: all changes queue and sync when back online.

        SMARTCOUNT (AI inventory input modes):
        - Photo Inventory: point camera at shelf — AI counts items and detects quantities. \
          Fluid mode available for liquid containers (estimates fill % and remaining volume).
        - Voice Inventory: speak items aloud — AI extracts item names and quantities. \
          Supports Indian English expressions (two and a half kilo, one dozen, etc.).
        - Sheet Inventory: photograph a handwritten or printed list — AI reads every row.
        - CSV/Excel Import: upload a spreadsheet, map columns, import in bulk.
        Free users: 3 AI uses/month per SmartCount mode. Pro: unlimited.

        PURCHASE INVOICE:
        - Scan a purchase invoice (photo or CSV) — AI extracts items and auto-matches to \
          existing inventory. Updates stock levels and records last purchase price.
        - Accessible from the Items tab (global entry) or from any Storage.

        SMART SALES:
        - Record sales by voice, photo, CSV, or manual entry.
        - Updates stock and records revenue.

        TEAM:
        - Invite team members to a shared workspace.
        - Roles: Owner (full access), Editor (add/edit items), Viewer (read only).
        - Pro feature.

        TEMPLATES:
        - Save any item as a template to reuse across storages.
        - Pro feature.

        PRO PLAN:
        - Unlimited storages, unlimited items per storage.
        - Unlimited AI uses for all SmartCount modes.
        - Unlimited team members.
        - Full analytics history (free plan: last 30 days only).
        - Barcode scanner pro (enriched product data).
        - Item photos.
        - Remove Ads (also available as a separate one-time purchase).
        - Stoqly has NO free trial. Users upgrade directly to Pro from Settings.
        - Subscription products: com.vishuddhi.stoqly.pro.monthly (monthly), \
          com.vishuddhi.stoqly.pro.annual (annual), com.vishuddhi.stoqly.removeads (one-time).

        HELP CENTRE:
        - Accessible from Settings — Support — Help & FAQ.
        - Contains searchable FAQ grouped by section.

        RULES FOR YOUR ANSWERS:
        - Answer only questions about Stoqly. If asked about anything unrelated, politely \
          say "I can only help with Stoqly questions."
        - Be concise and practical — users are busy SMB owners, not tech people.
        - Use simple language. No jargon.
        - If you don't know the answer, say "I'm not sure about that — please contact \
          support at support@stoqly.app."
        - Never mention competitors.
        - Never say Stoqly has a free trial — it does not.
        - Keep answers to 3–5 sentences max unless a step-by-step is genuinely needed.
        """

        return try await callClaudeRaw(
            systemPrompt: systemPrompt,
            userPrompt: question,
            imageDataList: [],
            maxTokens: 512
        )
    }

    // MARK: - Inventory sheet photo → items

    /// Takes a photo of a handwritten or printed inventory sheet and extracts
    /// every row as a structured item.
    func parseInventorySheet(
        imageData: Data,
        inventoryHints: [String] = [],
        appLanguageCode: String? = nil
    ) async throws -> [ParsedInventoryItem] {
        let inventoryHint = inventoryHints.prefix(50).joined(separator: ", ")
        let contextPrefix = inventoryHint.isEmpty
            ? ""
            : "The user's inventory includes: \(inventoryHint). If a row clearly matches one of these, return that existing item's EXACT stored name.\n\n"

        var prompt = """
        \(Self.expiryDateAnchorPrompt)

        \(contextPrefix)You are an inventory assistant. This is a photo of a physical inventory sheet (handwritten or printed).

        Extract every row you can read. Return a JSON array only, no explanation.

        Format:
        [
          {
            "name": "Olive Oil Extra Virgin 1L",
            "quantity": 4.0,
            "unit": "btl",
            "category": "Food & Beverage",
            "confidence": 0.90,
            "unitCost": null,
            "sellingPrice": null,
            "expiryDate": null,
            "sku": null,
            "barcode": null,
            "minQuantity": null,
            "notes": null
          }
        ]

        Rules:
        - Extract ALL rows visible in the sheet, even partially legible ones
        - "name": for PRINTED or branded names, keep the text EXACTLY as written on the sheet — do NOT translate brands or label text
        - "name": for handwritten generic items with no brand, keep the name in the language/script it was written in; do NOT translate to English
        - EXCEPTION: if a row clearly matches one already in the user's inventory list above, return that existing item's EXACT stored name (even if written in another language) so it updates that item instead of creating a duplicate
        - "quantity": the number written next to the item, null if missing or illegible
        - "unit": READ the unit directly from the sheet's unit column when one is present.
          If the sheet has no unit column, INFER the unit from the item name:
            • Bottles (wine, spirits, sauces, oils, water): "btl"
            • Cans or tins: "can"
            • Boxes or cases: "bx"
            • Bags (rice, flour, sugar, salt): "bag"
            • Rolls (paper towels, cling film): "roll"
            • Liquids by volume (oil, milk, juice, sauce): "L" or "mL"
            • Dry goods by weight (flour, sugar, rice, spice, coffee): "kg" or "g"
            • Individual pieces with no other unit: "pcs"
          Do NOT default everything to "pcs" — only use "pcs" when no other unit clearly fits.
        - "category": guess from item name: Food & Beverage, Cleaning & Hygiene, Packaging & Supplies, Electronics & Equipment, Clothing & Apparel, Health & Beauty, Pharmaceutical, Raw Materials, Spare Parts, Stationery & Office, Uncategorised
        - "confidence": lower (0.5–0.7) for hard-to-read handwriting or unclear items
        - Include all rows — the user will review and remove incorrect ones
        - Return [] only if the image contains no inventory data at all
        \(Self.optionalItemFieldsPrompt)
        \(Self.machineFieldsEnglishRule)
        """

        if let lang = appLanguageCode, lang != "en", !lang.isEmpty {
            prompt += "\n\n\(Self.appLanguageNameRule(for: lang))"
        }

        return try await callClaude(textPrompt: prompt, imageData: imageData)
    }

    // MARK: - Core API call

    private func callClaude(textPrompt: String, imageData: Data?) async throws -> [ParsedInventoryItem] {
        guard let apiKey = SecretsManager.effectiveAnthropicKey else {
            throw AIInventoryError.missingAPIKey
        }

        // Build message content
        var contentArray: [[String: Any]] = []

        // Attach image if provided
        if let imageData {
            let base64 = imageData.base64EncodedString()
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ] as [String: Any]
            ])
        }

        // Text prompt
        contentArray.append([
            "type": "text",
            "text": textPrompt
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048, // shelf scans can return 15–20 products
            "messages": [
                ["role": "user", "content": contentArray]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            throw AIInventoryError.networkError(error)
        }

        // Extract text content from response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIInventoryError.invalidResponse
        }

        return parseJSONResponse(text)
    }

    // MARK: - JSON → ParsedInventoryItem

    private func parseJSONResponse(_ text: String) -> [ParsedInventoryItem] {
        // Strip markdown code fences if present
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if clean.hasSuffix("```") {
                clean = String(clean.dropLast(3))
            }
        }

        guard let data = clean.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict -> ParsedInventoryItem? in
            guard let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }

            var qty: Double? = nil
            if let q = dict["quantity"] as? Double { qty = q }
            else if let q = dict["quantity"] as? Int { qty = Double(q) }

            let confidence = (dict["confidence"] as? Double) ?? 0.8

            var fillPercent: Double?
            if let f = dict["fillPercent"] as? Double { fillPercent = f }
            else if let f = dict["fillPercent"] as? Int { fillPercent = Double(f) }

            let remainingVolume = dict["remainingVolume"] as? String

            return ParsedInventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                quantity: qty,
                unitSymbol: dict["unit"] as? String,
                category: dict["category"] as? String,
                notes: dict["notes"] as? String,
                confidence: confidence,
                fillPercent: fillPercent,
                remainingVolume: remainingVolume,
                unitCost: Self.parseDouble(dict["unitCost"]),
                sellingPrice: Self.parseDouble(dict["sellingPrice"]),
                expiryDate: Self.parseExpiryDate(dict["expiryDate"]),
                sku: dict["sku"] as? String,
                barcode: dict["barcode"] as? String,
                minQuantity: Self.parseDouble(dict["minQuantity"])
            )
        }
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func parseExpiryDate(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: trimmed) { return date }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "dd-MM-yyyy", "dd/MM/yyyy"] {
            df.dateFormat = format
            if let date = df.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: - Smart Sales Entry

    private static let salesSystemPrompt = """
    You are a sales log parser for an inventory management app. Extract sale items from the input. \
    Return ONLY a valid JSON array. Each object: {"itemName": string, "quantitySold": number, \
    "pricePerUnit": number (0 if unknown), "notes": string, "confidence": number}. \
    No markdown, no explanation — just the JSON array.

    Item-name rules:
    - KEEP "itemName" in the SAME language/script the user spoke or wrote it — do NOT translate product names into English.
    - If an inventory list is provided and the item clearly matches one, use that inventory item's EXACT stored name.
    - Only use the spoken/written name for items that do not match the inventory list.
    - "confidence" 0.0-1.0 indicates how confident you are about that row's item name and quantity extraction.
    """

    private static let purchaseSystemPrompt = """
    You are parsing a supplier purchase invoice. Extract each line item: item name, quantity received, \
    and unit cost/price. Return ONLY a valid JSON array. Each object: {"itemName": string, \
    "quantityReceived": number, "costPerUnit": number (0 if unknown), "notes": string}. \
    No markdown, no explanation — just the JSON array.

    Item-name rules:
    - KEEP "itemName" as printed/written on the invoice — do NOT translate product names into English.
    - If an inventory list is provided and the line clearly matches one, use that inventory item's EXACT stored name.
    - Keep brand names and printed label text EXACTLY as shown on the invoice.
    """

    func parseSalesTranscript(transcript: String, knownItemNames: [String] = []) async throws -> [ParsedSaleRow] {
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))You are parsing a spoken sales log. Extract each item sold: name, quantity sold, and price per unit if mentioned.
        If price not mentioned, use 0.

        Transcript: "\(transcript)"
        """
        return try await callClaudeForSales(textPrompt: prompt, imageDataList: [])
    }

    func parseSalesText(text: String, knownItemNames: [String] = []) async throws -> [ParsedSaleRow] {
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Parse this sales list. Extract item name, quantity sold, and price per unit for each line.
        If price not mentioned, use 0.

        Input:
        \(text)
        """
        return try await callClaudeForSales(textPrompt: prompt, imageDataList: [])
    }

    func parseSalesImage(imageData: Data, knownItemNames: [String] = []) async throws -> [ParsedSaleRow] {
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Extract all sale items from this image. Look for item names, quantities sold, and prices.
        This may be a receipt, handwritten chit, or sales sheet. If price not visible, use 0.
        """
        return try await callClaudeForSales(textPrompt: prompt, imageDataList: [imageData])
    }

    func parseSalesPDF(pages: [UIImage], knownItemNames: [String] = []) async throws -> [ParsedSaleRow] {
        let imageDataList = pages.compactMap { $0.jpegData(compressionQuality: 0.85) }
        guard !imageDataList.isEmpty else { throw AIInventoryError.noItemsFound }
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Extract all sale items from these PDF page images. Look for item names, quantities sold, and prices.
        If price not visible, use 0.
        """
        return try await callClaudeForSales(textPrompt: prompt, imageDataList: imageDataList)
    }

    private static func inventoryContext(for knownItemNames: [String]) -> String {
        guard !knownItemNames.isEmpty else { return "" }
        return """
        Inventory items available: \(knownItemNames.joined(separator: ", ")).
        Use the EXACT inventory name when the item mentioned or shown clearly matches one of these (even if spoken/written in another language).
        Only use the spoken/written name for NEW items that do not match the inventory list.
        Do NOT translate product names into English — keep the original language unless returning an exact inventory match.

        """
    }

    func parsePurchaseInvoiceImage(imageData: Data, knownItemNames: [String] = []) async throws -> [ParsedPurchaseRow] {
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Extract all purchase line items from this supplier invoice image: item name, quantity received, unit cost.
        Keep each item name as printed on the invoice. If price not visible, use 0.
        """
        return try await callClaudeForPurchase(textPrompt: prompt, imageDataList: [imageData])
    }

    func parsePurchaseInvoicePDF(pages: [UIImage], knownItemNames: [String] = []) async throws -> [ParsedPurchaseRow] {
        let imageDataList = pages.compactMap { $0.jpegData(compressionQuality: 0.85) }
        guard !imageDataList.isEmpty else { throw AIInventoryError.noItemsFound }
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Extract all purchase line items from these invoice PDF pages.
        Keep each item name as printed on the invoice. If cost not visible, use 0.
        """
        return try await callClaudeForPurchase(textPrompt: prompt, imageDataList: imageDataList)
    }

    func parsePurchaseInvoiceCSV(text: String, knownItemNames: [String] = []) async throws -> [ParsedPurchaseRow] {
        let prompt = """
        \(Self.inventoryContext(for: knownItemNames))Parse this supplier delivery note / invoice spreadsheet text. Extract item name, quantity received, unit cost.
        Keep each item name as written in the source. If cost not visible, use 0.

        \(text)
        """
        return try await callClaudeForPurchase(textPrompt: prompt, imageDataList: [])
    }

    func suggestSalesColumnMapping(headers: [String], sampleRow: [String]) async throws -> [String: String] {
        let headerList = headers.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let sampleList = sampleRow.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let prompt = """
        You are mapping spreadsheet columns for a sales import. Available fields: "Item Name", "Quantity", "Price Per Unit", "Date", "Notes", "— Skip —".
        Headers: \(headerList)
        First data row: \(sampleList)
        Reply with ONLY a JSON object mapping column index (as string) to field name. Example: {"0":"Item Name","1":"Quantity","2":"Price Per Unit","3":"— Skip —"}
        Map every column index. Use "— Skip —" for unrecognised columns.
        """
        let text = try await callClaudeRaw(
            systemPrompt: "You map spreadsheet columns to import fields. Reply with JSON only.",
            userPrompt: prompt,
            imageDataList: [],
            maxTokens: 200
        )
        return try parseColumnMappingJSON(text)
    }

    func suggestPurchaseColumnMapping(headers: [String], sampleRow: [String]) async throws -> [String: String] {
        let headerList = headers.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let sampleList = sampleRow.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let prompt = """
        You are mapping spreadsheet columns for a purchase invoice import. Available fields: "Item Name", "Quantity", "Unit Cost", "Notes", "— Skip —".
        Headers: \(headerList)
        First data row: \(sampleList)
        Reply with ONLY a JSON object mapping column index (as string) to field name. Example: {"0":"Item Name","1":"Quantity","2":"Unit Cost"}
        Map every column index. Use "— Skip —" for unrecognised columns.
        """
        let text = try await callClaudeRaw(
            systemPrompt: "You map spreadsheet columns to import fields. Reply with JSON only.",
            userPrompt: prompt,
            imageDataList: [],
            maxTokens: 200
        )
        return try parseColumnMappingJSON(text)
    }

    func suggestCountColumnMapping(headers: [String], sampleRow: [String]) async throws -> [String: String] {
        let headerList = headers.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let sampleList = sampleRow.enumerated().map { "Column \($0.offset): \"\($0.element)\"" }.joined(separator: ", ")
        let prompt = """
        You are mapping spreadsheet columns for an inventory count import. Available fields: "Item Name", "Quantity", "— Skip —".
        Headers: \(headerList)
        First data row: \(sampleList)
        Reply with ONLY a JSON object mapping column index (as string) to field name. Example: {"0":"Item Name","1":"Quantity"}
        Map every column index. Use "— Skip —" for unrecognised columns.
        """
        let text = try await callClaudeRaw(
            systemPrompt: "You map spreadsheet columns to import fields. Reply with JSON only.",
            userPrompt: prompt,
            imageDataList: [],
            maxTokens: 200
        )
        return try parseColumnMappingJSON(text)
    }

    private func parseColumnMappingJSON(_ text: String) throws -> [String: String] {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if clean.hasSuffix("```") { clean = String(clean.dropLast(3)) }
            clean = clean.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        guard let data = clean.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw AIInventoryError.invalidResponse
        }
        return json
    }

    private func callClaudeForSales(textPrompt: String, imageDataList: [Data]) async throws -> [ParsedSaleRow] {
        let text = try await callClaudeRaw(systemPrompt: Self.salesSystemPrompt, userPrompt: textPrompt, imageDataList: imageDataList)
        let dtos = try decodeJSON(text, as: [ParsedSaleRowDTO].self)
        let rows = dtos.map { $0.toParsedSaleRow() }.filter { !$0.itemName.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { throw AIInventoryError.noItemsFound }
        return rows
    }

    private func callClaudeForPurchase(textPrompt: String, imageDataList: [Data]) async throws -> [ParsedPurchaseRow] {
        let text = try await callClaudeRaw(systemPrompt: Self.purchaseSystemPrompt, userPrompt: textPrompt, imageDataList: imageDataList)
        let dtos = try decodeJSON(text, as: [ParsedPurchaseRowDTO].self)
        let rows = dtos.map { $0.toParsedPurchaseRow() }.filter { !$0.itemName.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { throw AIInventoryError.noItemsFound }
        return rows
    }

    private func callClaudeRaw(systemPrompt: String, userPrompt: String, imageDataList: [Data], maxTokens: Int = 4096) async throws -> String {
        guard let apiKey = SecretsManager.effectiveAnthropicKey else {
            throw AIInventoryError.missingAPIKey
        }

        var contentArray: [[String: Any]] = []
        for imageData in imageDataList {
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ] as [String: Any]
            ])
        }
        contentArray.append(["type": "text", "text": userPrompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [["role": "user", "content": contentArray]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            throw AIInventoryError.networkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIInventoryError.invalidResponse
        }
        return text
    }

    private func decodeJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if clean.hasSuffix("```") { clean = String(clean.dropLast(3)) }
            clean = clean.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        guard let data = clean.data(using: .utf8) else { throw AIInventoryError.invalidResponse }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIInventoryError.invalidResponse
        }
    }
}
