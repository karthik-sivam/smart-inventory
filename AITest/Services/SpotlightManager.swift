@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes `InventoryItem` records in Core Spotlight so users can open stock
/// from the iOS home-screen search field or Siri without launching Stoqly first.
final class SpotlightManager: Sendable {
    static let shared = SpotlightManager()
    private let domainIdentifier = "com.vishuddhi.stoqly.items"

    private init() {}

    /// Index (add or update) a single item.
    func index(_ item: InventoryItem) {
        CSSearchableIndex.default().indexSearchableItems([makeSearchableItem(for: item)]) { _ in }
    }

    /// Remove a single item from the index.
    func deindex(_ item: InventoryItem) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [item.id.uuidString]
        ) { _ in }
    }

    /// Re-index all items (call once after sign-in or bulk cloud pull).
    func reindexAll(_ items: [InventoryItem]) {
        let searchableItems = items.map { makeSearchableItem(for: $0) }
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { _ in
            guard !searchableItems.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(searchableItems) { _ in }
        }
    }

    private func makeSearchableItem(for item: InventoryItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = item.name

        var descriptionParts: [String] = [item.category]
        if let storageName = item.storage?.name {
            descriptionParts.append("in \(storageName)")
        }
        if item.isOutOfStock {
            descriptionParts.append("Out of stock")
        } else if item.isLowStock {
            descriptionParts.append("Low stock")
        }
        attributeSet.contentDescription = descriptionParts.joined(separator: " · ")

        attributeSet.keywords = [item.sku, item.barcode, item.category].filter { !$0.isEmpty }

        return CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }
}
