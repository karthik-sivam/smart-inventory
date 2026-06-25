import SwiftUI
import SwiftData

struct CategoryExplorerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [InventoryItem]
    @State private var selectedCategory: String? = nil
    @State private var selectedItem: InventoryItem? = nil

    private var filteredItems: [InventoryItem] {
        guard let cat = selectedCategory else { return items.sorted { $0.name < $1.name } }
        return items.filter { $0.category == cat }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    CategoryDonutChart(
                        items: Array(items),
                        selectedCategory: selectedCategory,
                        onCategoryTapped: { tapped in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedCategory = (selectedCategory == tapped) ? nil : tapped
                            }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)

                    HStack {
                        Text(selectedCategory == nil
                             ? "All Items (\(items.count))"
                             : "\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        if selectedCategory != nil {
                            Button("Clear") {
                                withAnimation { selectedCategory = nil }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    LazyVStack(spacing: 12) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "cube.box")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No items in this category")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filteredItems, id: \.id) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    ItemRowView(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .navigationTitle("Items by Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                AnalyticsManager.shared.track(.categoryExplorerViewed)
            }
        }
        .sheet(item: $selectedItem) { item in
            // B6: ItemDetailView no longer wraps itself in a NavigationStack.
            NavigationStack {
                ItemDetailView(item: item)
            }
            .sheetStyle()
        }
    }
}
