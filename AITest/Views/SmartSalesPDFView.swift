import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

struct SmartSalesPDFView: View {
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @State private var step: PDFStep = .pick
    @State private var pdfURL: URL?
    @State private var parsedRows: [ParsedSaleRow] = []
    @State private var analyzeProgress = ""
    @State private var errorMessage: String?
    @State private var showingFilePicker = false

    enum PDFStep { case pick, analyzing, review }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick: pickView
                case .analyzing: analyzingView
                case .review:
                    SaleEntryReviewView(
                        rows: $parsedRows,
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = .pick }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle(step == .review ? "Review Sales" : "PDF Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                pdfURL = url
            }
        }
    }

    private var pickView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.fill").font(.system(size: 48)).foregroundColor(.orange.opacity(0.7))
            Text("Select a PDF").font(.title3).fontWeight(.semibold)
            Text("Works with invoices, supplier sales sheets, or any PDF with item names and quantities.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Choose PDF") { showingFilePicker = true }
                .buttonStyle(.bordered).tint(.orange).controlSize(.large)
            if let name = pdfURL?.lastPathComponent {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").foregroundColor(.orange)
                    Text(name).font(.subheadline).lineLimit(1)
                }
                .padding(12).background(Color.orange.opacity(0.08)).cornerRadius(10)
                Button("Analyse PDF") { analyzePDF() }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.stoqlyDanger)
            }
            Spacer()
        }
        .padding()
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Reading your PDF…").font(.subheadline).foregroundColor(.secondary)
            if !analyzeProgress.isEmpty {
                Text(analyzeProgress).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func analyzePDF() {
        guard let url = pdfURL else { return }
        step = .analyzing
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else { throw URLError(.fileDoesNotExist) }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let pdf = PDFDocument(url: url) else { throw URLError(.cannotOpenFile) }
                let maxPages = min(pdf.pageCount, 10)
                if pdf.pageCount > 10 {
                    analyzeProgress = "Large PDF detected — analysing first 10 of \(pdf.pageCount) pages"
                }
                var images: [UIImage] = []
                for i in 0..<maxPages {
                    analyzeProgress = "Processing page \(i + 1) of \(maxPages)…"
                    if let page = pdf.page(at: i) {
                        images.append(page.thumbnail(of: CGSize(width: 1024, height: 1400), for: .mediaBox))
                    }
                }
                parsedRows = try await AIInventoryService.shared.parseSalesPDF(
                    pages: images,
                    knownItemNames: allItems.map(\.name)
                )
                AnalyticsManager.shared.track(.smartSalesModeSelected(mode: "pdf"))
                step = .review
            } catch {
                errorMessage = error.localizedDescription
                step = .pick
            }
        }
    }
}
