import SwiftUI
import SwiftData

struct SmartSalesTextView: View {
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @State private var inputText = ""
    @State private var parsedRows: [ParsedSaleRow] = []
    @State private var step: TextStep = .input
    @State private var errorMessage: String?

    enum TextStep { case input, analyzing, review }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .input: inputView
                case .analyzing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Parsing your text…").font(.subheadline).foregroundColor(.secondary)
                    }
                case .review:
                    SaleEntryReviewView(
                        rows: $parsedRows,
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = .input }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle(step == .review ? "Review Sales" : "Text Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 16) {
            TextEditor(text: $inputText)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                .accessibilityIdentifier("smartSalesTextInput")
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Type or paste a sales list, e.g.:\n5 chips\n2 waters\n1 sandwich")
                            .foregroundColor(.secondary).font(.body).padding(8).allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundColor(.stoqlyAccent)
                Text("Include quantity and price. One item per line works best.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(12).background(Color(.tertiarySystemGroupedBackground)).cornerRadius(10)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.stoqlyDanger)
            }

            Button("Parse Sales") { parseText() }
                .buttonStyle(.borderedProminent).tint(.stoqlyAccent).controlSize(.large)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("smartSalesParseButton")

            Spacer()
        }
        .padding()
    }

    private func parseText() {
        step = .analyzing
        Task {
            do {
                parsedRows = try await AIInventoryService.shared.parseSalesText(
                    text: inputText,
                    knownItemNames: allItems.map(\.name)
                )
                AnalyticsManager.shared.track(.smartSalesModeSelected(mode: "text"))
                step = .review
            } catch {
                errorMessage = error.localizedDescription
                step = .input
            }
        }
    }
}
