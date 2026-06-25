import Foundation

/// Persists the user's last few global-search queries in UserDefaults so they
/// can be re-run from dismissible chips in `GlobalSearchView`.
@MainActor
final class SearchHistoryManager: ObservableObject {
    private static let key = "stoqly_searchHistory"
    private let maxItems = 5

    @Published private(set) var queries: [String] = []

    init() { load() }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = queries.filter { $0 != trimmed }
        current.insert(trimmed, at: 0)
        queries = Array(current.prefix(maxItems))
        save()
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        save()
    }

    func clear() {
        queries = []
        save()
    }

    private func load() {
        queries = (UserDefaults.standard.array(forKey: Self.key) as? [String]) ?? []
    }

    private func save() {
        UserDefaults.standard.set(queries, forKey: Self.key)
    }
}
