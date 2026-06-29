import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct PurchaseInvoiceImportView: View {
    let defaultStorage: Storage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var showingPhoto = false
    @State private var showingPDF = false
    @State private var showingCSV = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.stoqlyPrimary)
                        Text("Import Invoice")
                            .font(.title2).fontWeight(.bold)
                        Text("Upload a supplier invoice for \(defaultStorage.name). AI extracts items — you review before stock is updated.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    modeCard(icon: "camera.fill", title: "Photo", color: .stoqlyAccent) { showingPhoto = true }
                    modeCard(icon: "doc.fill", title: "PDF", color: .orange) { showingPDF = true }
                    modeCard(icon: "tablecells", title: "CSV / Excel", color: .green) { showingCSV = true }

                    if !subscriptionManager.isPro {
                        Text("Invoice import requires Pro")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingPhoto) {
            PurchaseInvoicePhotoView(defaultStorage: defaultStorage)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingPDF) {
            PurchaseInvoicePDFView(defaultStorage: defaultStorage)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingCSV) {
            PurchaseInvoiceCSVView(defaultStorage: defaultStorage)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "pro_feature").sheetStyle()
        }
    }

    private func modeCard(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        let isPro = subscriptionManager.isPro
        return Button(action: isPro ? action : { showingPaywall = true }) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3).foregroundColor(isPro ? color : .secondary)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(isPro ? 0.12 : 0.06))
                    .cornerRadius(10)
                Text(title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Image(systemName: isPro ? "chevron.right" : "lock.fill")
                    .font(.caption).foregroundColor(isPro ? .secondary : .orange)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("purchaseInvoiceMode_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

// MARK: - Photo mode

struct PurchaseInvoicePhotoView: View {
    let defaultStorage: Storage
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var parsedRows: [ParsedPurchaseRow] = []
    @State private var step: Int = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { captureStep }
                else if step == 1 {
                    VStack { ProgressView(); Text("Analysing invoice…") }
                } else {
                    PurchaseReviewView(
                        rows: $parsedRows,
                        defaultStorage: defaultStorage,
                        onConfirm: { dismiss() },
                        onCancel: { step = 0 }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle("Photo Invoice")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, img in
            guard let img else { return }
            Task { await analyze(img) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await analyze(img)
                }
            }
        }
    }

    private var captureStep: some View {
        VStack(spacing: 16) {
            Button { showingCamera = true } label: {
                Label("Take Photo", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent).tint(.stoqlyAccent)
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose from Library", systemImage: "photo")
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red) }
            Spacer()
        }
        .padding()
    }

    private func analyze(_ image: UIImage) async {
        step = 1
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "Could not process image."
            step = 0
            return
        }
        do {
            parsedRows = try await AIInventoryService.shared.parsePurchaseInvoiceImage(imageData: data)
            step = 2
        } catch {
            errorMessage = error.localizedDescription
            step = 0
        }
    }
}

// MARK: - PDF mode

struct PurchaseInvoicePDFView: View {
    let defaultStorage: Storage
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var pdfURL: URL?
    @State private var parsedRows: [ParsedPurchaseRow] = []
    @State private var step = 0
    @State private var showingFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { pickStep }
                else if step == 1 { ProgressView("Reading PDF…") }
                else {
                    PurchaseReviewView(
                        rows: $parsedRows,
                        defaultStorage: defaultStorage,
                        onConfirm: { dismiss() },
                        onCancel: { step = 0 }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle("PDF Invoice")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { pdfURL = url }
        }
    }

    private var pickStep: some View {
        VStack(spacing: 16) {
            Button("Choose PDF") { showingFilePicker = true }
                .buttonStyle(.borderedProminent).tint(.orange)
            if pdfURL != nil {
                Button("Analyse PDF") { analyzePDF() }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red) }
            Spacer()
        }
        .padding()
    }

    private func analyzePDF() {
        guard let url = pdfURL else { return }
        step = 1
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else { throw URLError(.fileDoesNotExist) }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let pdf = PDFDocument(url: url) else { throw URLError(.cannotOpenFile) }
                let maxPages = min(pdf.pageCount, 10)
                var images: [UIImage] = []
                for i in 0..<maxPages {
                    if let page = pdf.page(at: i) {
                        images.append(page.thumbnail(of: CGSize(width: 1024, height: 1400), for: .mediaBox))
                    }
                }
                parsedRows = try await AIInventoryService.shared.parsePurchaseInvoicePDF(pages: images)
                step = 2
            } catch {
                errorMessage = error.localizedDescription
                step = 0
            }
        }
    }
}

// MARK: - CSV mode

struct PurchaseInvoiceCSVView: View {
    let defaultStorage: Storage
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @StateObject private var vm = SmartSalesCSVViewModel()
    @State private var showFilePicker = false
    @State private var parsedRows: [ParsedPurchaseRow] = []
    @State private var showingReview = false

    var body: some View {
        NavigationStack {
            Form {
                Button("Choose CSV or Excel") { showFilePicker = true }
                if vm.step >= 1 {
                    Text("\(vm.rows.count) rows loaded — map Item Name, Quantity, and Unit Cost columns in the file picker flow.")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Convert & Review") {
                        parsedRows = vm.buildParsedRows().map {
                            ParsedPurchaseRow(
                                itemName: $0.itemName,
                                quantityReceived: $0.quantitySold,
                                costPerUnit: $0.pricePerUnit,
                                notes: $0.notes
                            )
                        }
                        showingReview = true
                    }
                }
            }
            .navigationTitle("CSV Invoice")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .commaSeparatedText,
                UTType(filenameExtension: "csv") ?? .plainText,
                UTType(filenameExtension: "xlsx") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.loadFile(from: url)
            }
        }
        .sheet(isPresented: $showingReview) {
            PurchaseReviewView(
                rows: $parsedRows,
                defaultStorage: defaultStorage,
                onConfirm: { dismiss() },
                onCancel: { showingReview = false }
            )
            .environmentObject(currencyManager)
            .sheetStyle()
        }
    }
}
