import Foundation
import SwiftData

/// Session queue for Pro bulk barcode scan. No `ModelContext` — the view saves.
@MainActor
final class BulkBarcodeScanViewModel: ObservableObject {

    struct CatalogItem {
        let id: UUID
        let name: String
        let barcode: String
    }

    struct QueuedRow: Identifiable, Equatable {
        let id: UUID
        let code: String
        var symbology: String
        var existingItemId: UUID?
        var existingName: String?
        var name: String
        var category: String
        var quantity: Double
        var isSelected: Bool

        var isExisting: Bool { existingItemId != nil }

        var badgeLabel: String {
            if isExisting {
                let base = existingName ?? name
                return "+\(quantity.smartFormatted) on \(base)"
            }
            return "New"
        }
    }

    @Published private(set) var rows: [QueuedRow] = []
    @Published private(set) var lastCode: String?
    @Published var errorMessage: String?

    let startedAt: CFAbsoluteTime
    var cooldownSeconds: CFAbsoluteTime = 1.2
    private var catalog: [CatalogItem] = []
    private var lastAcceptAt: [String: CFAbsoluteTime] = [:]

    init(startedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        self.startedAt = startedAt
    }

    var scannedCount: Int { rows.count }

    var selectedRows: [QueuedRow] { rows.filter(\.isSelected) }

    var durationMs: Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000))
    }

    func bind(catalog: [CatalogItem]) {
        self.catalog = catalog
    }

    func bind(items: [InventoryItem]) {
        bind(catalog: items.compactMap { item in
            let code = Self.normalize(item.barcode)
            guard !code.isEmpty else { return nil }
            return CatalogItem(id: item.id, name: item.name, barcode: code)
        })
    }

    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func defaultName(for code: String) -> String {
        "Scanned \(code)"
    }

    /// Returns true when the code was accepted (new row or qty bump).
    @discardableResult
    func ingest(code: String, symbology: String) -> Bool {
        let normalized = Self.normalize(code)
        guard !normalized.isEmpty else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastAcceptAt[normalized], now - last < cooldownSeconds {
            return false
        }
        lastAcceptAt[normalized] = now
        lastCode = normalized

        if let index = rows.firstIndex(where: { $0.code == normalized }) {
            rows[index].quantity += 1
            return true
        }

        let match = catalog.first { $0.barcode.caseInsensitiveCompare(normalized) == .orderedSame }
        let row = QueuedRow(
            id: UUID(),
            code: normalized,
            symbology: symbology,
            existingItemId: match?.id,
            existingName: match?.name,
            name: match?.name ?? Self.defaultName(for: normalized),
            category: "Uncategorised",
            quantity: 1,
            isSelected: true
        )
        rows.append(row)
        return true
    }

    func setQuantity(id: UUID, quantity: Double) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].quantity = max(1, quantity)
    }

    func setName(id: UUID, name: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard !rows[index].isExisting else { return }
        rows[index].name = name
    }

    func setSelected(id: UUID, selected: Bool) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isSelected = selected
    }

    func remove(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    func applyEnrichment(code: String, name: String, category: String) {
        let normalized = Self.normalize(code)
        guard let index = rows.firstIndex(where: { $0.code == normalized && !$0.isExisting }) else { return }
        if rows[index].name == Self.defaultName(for: normalized) {
            rows[index].name = name
            rows[index].category = category
        }
    }
}
