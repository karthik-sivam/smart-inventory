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

    // MARK: - Voice transcript → items

    /// Takes the raw text from SFSpeechRecognizer and returns a list of items
    /// the user mentioned. Handles natural speech like "5 kg of flour, 2 boxes
    /// of sugar, and we're out of salt".
    func parseVoiceTranscript(_ transcript: String) async throws -> [ParsedInventoryItem] {
        let prompt = """
        You are an inventory assistant. The user has dictated an inventory count verbally.

        Transcript: "\(transcript)"

        Extract each inventory item mentioned. Return a JSON array only, no explanation.

        Format:
        [
          {
            "name": "item name",
            "quantity": 5.0,
            "unit": "kg",
            "category": "Food & Beverage",
            "confidence": 0.95
          }
        ]

        Rules:
        - "name" must be a clean product name (e.g. "Flour", not "5 kg of flour")
        - "quantity" is a number, null if not mentioned
        - "unit" use standard abbreviations: pcs, kg, g, L, mL, m, cm. null if unclear
        - "category" must be one of: Food & Beverage, Cleaning & Hygiene, Packaging & Supplies, Electronics & Equipment, Clothing & Apparel, Health & Beauty, Pharmaceutical, Raw Materials, Spare Parts, Stationery & Office, Uncategorised
        - "confidence" 0.0-1.0 how confident you are this is a real inventory item
        - Skip filler words and conversation
        - Return [] if nothing recognisable was said
        """

        return try await callClaude(textPrompt: prompt, imageData: nil)
    }

    // MARK: - Product photo → item

    /// Takes a photo of a product or shelf and returns the identified product
    /// WITH a counted quantity based on what is visible in the frame.
    func identifyProduct(imageData: Data) async throws -> [ParsedInventoryItem] {
        let prompt = """
        You are an inventory counting assistant. Carefully examine this photo.

        Your two jobs:
        1. Identify what product(s) are shown.
        2. COUNT how many units are visible.

        Counting rules:
        - Count every individual unit you can see (bottles, boxes, cans, bags, etc.)
        - If items are arranged in rows and columns, count all cells visible (rows × columns),
          including partially visible units at the edges.
        - If items are stacked and some are hidden behind others, estimate the total:
          count the front row/layer and multiply by how many layers deep you can infer.
        - If it is clearly a single item, quantity = 1.
        - Never leave quantity null — always give your best estimate.

        Return a JSON array with one entry per distinct product type. No explanation.

        Format:
        [
          {
            "name": "product name",
            "quantity": 12.0,
            "unit": "pcs",
            "category": "Food & Beverage",
            "confidence": 0.85
          }
        ]

        Rules:
        - "name": brand + type where visible (e.g. "Heinz Tomato Ketchup 500ml")
        - "quantity": counted or estimated number of units — never null
        - "unit": infer from product type (bottles/cans/boxes → "pcs", loose flour → "kg", liquids → "L")
        - "category": one of: Food & Beverage, Cleaning & Hygiene, Packaging & Supplies,
          Electronics & Equipment, Clothing & Apparel, Health & Beauty, Pharmaceutical,
          Raw Materials, Spare Parts, Stationery & Office, Uncategorised
        - "confidence": 0.0–1.0 — lower when counting is uncertain due to occlusion or blur
        - Return [] only if the image is completely unidentifiable
        """

        return try await callClaude(textPrompt: prompt, imageData: imageData)
    }

    // MARK: - Inventory sheet photo → items

    /// Takes a photo of a handwritten or printed inventory sheet and extracts
    /// every row as a structured item.
    func parseInventorySheet(imageData: Data) async throws -> [ParsedInventoryItem] {
        let prompt = """
        You are an inventory assistant. This is a photo of a physical inventory sheet (handwritten or printed).

        Extract every row you can read. Return a JSON array only, no explanation.

        Format:
        [
          {
            "name": "Olive Oil Extra Virgin 1L",
            "quantity": 4.0,
            "unit": "btl",
            "category": "Food & Beverage",
            "confidence": 0.90
          }
        ]

        Rules:
        - Extract ALL rows visible in the sheet, even partially legible ones
        - "name": the product name as written — clean up obvious abbreviations (e.g. "OlvOil" → "Olive Oil", "Chckn stk" → "Chicken Stock")
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
        """

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

            return ParsedInventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                quantity: qty,
                unitSymbol: dict["unit"] as? String,
                category: dict["category"] as? String,
                notes: dict["notes"] as? String,
                confidence: confidence
            )
        }
    }
}
