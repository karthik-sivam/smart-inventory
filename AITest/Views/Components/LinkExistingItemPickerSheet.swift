import SwiftUI
import SwiftData

// MARK: - Name similarity (nearest-match suggestions)

enum ItemNameMatcher {
    static func score(query: String, candidate: String) -> Int {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let c = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !c.isEmpty else { return 0 }

        if q == c { return 1000 }
        if c.contains(q) { return 800 + q.count }
        if q.contains(c) { return 700 + c.count }

        let qWords = Set(q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let cWords = Set(c.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let overlap = qWords.intersection(cWords).filter { $0.count >= 2 }
        if !overlap.isEmpty { return 400 + overlap.count * 80 }

        if c.hasPrefix(q) || q.hasPrefix(c) { return 300 }

        let distance = levenshtein(q, c)
        let maxLen = max(q.count, c.count)
        guard maxLen > 0 else { return 0 }
        let similarity = Double(maxLen - distance) / Double(maxLen)
        if similarity >= 0.55 { return Int(similarity * 200) }

        return 0
    }

    static func nearestMatches(query: String, in items: [InventoryItem], limit: Int = 8) -> [InventoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return items
            .map { ($0, score(query: trimmed, candidate: $0.name)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        for (i, aChar) in aChars.enumerated() {
            var current = [i + 1]
            for (j, bChar) in bChars.enumerated() {
                let insertions = previous[j + 1] + 1
                let deletions = current[j] + 1
                let substitutions = previous[j] + (aChar == bChar ? 0 : 1)
                current.append(min(insertions, deletions, substitutions))
            }
            previous = current
        }
        return previous[bChars.count]
    }
}

// MARK: - Link existing picker sheet

struct LinkExistingItemPickerSheet: View {
    let parsedName: String
    let selectedStorage: Storage?
    @Binding var match: EditableItem.ItemMatch

    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [InventoryItem]

    @State private var searchText = ""

    private var itemPool: [InventoryItem] {
        if let storage = selectedStorage {
            return storage.items
        }
        return allItems
    }

    private var suggestedMatches: [InventoryItem] {
        ItemNameMatcher.nearestMatches(query: parsedName, in: itemPool)
    }

    private var searchResults: [InventoryItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return itemPool
            .filter {
                $0.name.localizedCaseInsensitiveContains(term) ||
                $0.sku.localizedCaseInsensitiveContains(term)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var showsAllStorages: Bool { selectedStorage == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(
                    text: $searchText,
                    placeholder: showsAllStorages ? "Search all items…" : "Search in \(selectedStorage?.name ?? "storage")…"
                )
                .padding(.horizontal)
                .padding(.vertical, 10)

                List {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if suggestedMatches.isEmpty {
                            Section {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No close matches found")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Search for the item you want to link to.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .listRowBackground(Color.clear)
                            }
                        } else {
                            Section("Suggested matches") {
                                ForEach(suggestedMatches, id: \.id) { item in
                                    linkRow(for: item)
                                }
                            }
                        }
                    } else if searchResults.isEmpty {
                        Section {
                            Text("No items match \"\(searchText)\"")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        Section("Results") {
                            ForEach(searchResults, id: \.id) { item in
                                linkRow(for: item)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Link to Existing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func linkRow(for item: InventoryItem) -> some View {
        Button {
            match = .existing(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        if showsAllStorages, let storageName = item.storage?.name {
                            Text(storageName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text("\(item.currentQuantity.smartFormatted) \(item.uom?.symbol ?? "pcs")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundColor(.stoqlyPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
