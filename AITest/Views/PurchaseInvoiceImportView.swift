import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import SwiftData

struct PurchaseInvoiceImportView: View {
    let defaultStorage: Storage?
    var onCompleted: (() -> Void)? = nil

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
                        if let storage = defaultStorage {
                            Text("Upload a supplier invoice for \(storage.name). AI extracts items — you review before stock is updated.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("AI extracts items across all your storages — review and assign storage before saving.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
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
        .onAppear {
            AnalyticsManager.shared.track(.purchaseEntryStarted(mode: "invoice"))
        }
        .sheet(isPresented: $showingPhoto) {
            PurchaseInvoicePhotoView(
                defaultStorage: defaultStorage,
                onCompleted: { onCompleted?(); dismiss() }
            )
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingPDF) {
            PurchaseInvoicePDFView(
                defaultStorage: defaultStorage,
                onCompleted: { onCompleted?(); dismiss() }
            )
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingCSV) {
            PurchaseInvoiceCSVView(
                defaultStorage: defaultStorage,
                onCompleted: { onCompleted?(); dismiss() }
            )
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
    let defaultStorage: Storage?
    var onCompleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

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
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = 0 }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle("Photo Invoice")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step < 2 {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
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
            parsedRows = try await AIInventoryService.shared.parsePurchaseInvoiceImage(
                imageData: data,
                knownItemNames: Array(allItems.prefix(50).map(\.name))
            )
            step = 2
        } catch {
            errorMessage = error.localizedDescription
            step = 0
        }
    }
}

// MARK: - PDF mode

struct PurchaseInvoicePDFView: View {
    let defaultStorage: Storage?
    var onCompleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @State private var pdfURL: URL?
    @State private var pdfThumbnail: UIImage?
    @State private var pdfFileName: String?
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
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = 0 }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle("PDF Invoice")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step < 2 {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { pdfURL = url }
        }
        .onChange(of: pdfURL) { _, url in
            guard let url else {
                pdfThumbnail = nil
                pdfFileName = nil
                return
            }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            pdfFileName = url.lastPathComponent
            if let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) {
                pdfThumbnail = page.thumbnail(of: CGSize(width: 280, height: 360), for: .mediaBox)
            }
        }
    }

    private var pickStep: some View {
        VStack(spacing: 16) {
            Button("Choose PDF") { showingFilePicker = true }
                .buttonStyle(.borderedProminent).tint(.orange)
            if pdfURL != nil {
                if let thumb = pdfThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                }
                if let pdfFileName {
                    Text(pdfFileName)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Button("Analyse PDF") { analyzePDF() }
                    .buttonStyle(.borderedProminent).tint(.orange)
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
                parsedRows = try await AIInventoryService.shared.parsePurchaseInvoicePDF(
                    pages: images,
                    knownItemNames: Array(allItems.prefix(50).map(\.name))
                )
                step = 2
            } catch {
                errorMessage = error.localizedDescription
                step = 0
            }
        }
    }
}

// MARK: - CSV mode

enum PurchaseImportField: String, CaseIterable, Identifiable {
    case itemName = "Item Name"
    case quantity = "Quantity"
    case costPerUnit = "Unit Cost"
    case notes = "Notes"
    case skip = "— Skip —"

    var id: String { rawValue }
}

@MainActor
final class PurchaseInvoiceCSVViewModel: ObservableObject {
    @Published var step = 0
    @Published var headers: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnMapping: [Int: PurchaseImportField] = [:]
    @Published var parseError: String?
    @Published var isSuggestingMappings = false

    var previewRows: [[String]] { Array(rows.prefix(5)) }

    var canProceedToPreview: Bool {
        columnMapping.values.contains(.itemName) && !rows.isEmpty
    }

    func loadFile(from url: URL) {
        parseError = nil
        let ext = url.pathExtension.lowercased()
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let grid: [[String]]
            if ext == "xlsx" || ext == "xlsm" {
                grid = try XLSXParser.parse(url: url)
            } else {
                let raw = try String(contentsOf: url, encoding: .utf8)
                grid = parseCSV(raw)
            }
            guard grid.count >= 2 else {
                parseError = "The file appears empty. Make sure it has a header row and at least one data row."
                return
            }
            let headerIdx = XLSXParser.findHeaderRow(in: grid)
            headers = grid[headerIdx].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = Array(grid[(headerIdx + 1)...]).filter { $0.contains(where: { !$0.isEmpty }) }
            autoDetect()
            step = 1
            Task { await aiEnhanceMapping() }
        } catch {
            parseError = "Could not read file: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func aiEnhanceMapping() async {
        guard !headers.isEmpty, !rows.isEmpty else { return }
        isSuggestingMappings = true
        defer { isSuggestingMappings = false }
        do {
            let sample = rows.first ?? []
            let suggestions = try await AIInventoryService.shared.suggestPurchaseColumnMapping(headers: headers, sampleRow: sample)
            for (indexStr, fieldName) in suggestions {
                guard let index = Int(indexStr) else { continue }
                let matched = PurchaseImportField.allCases.first { $0.rawValue == fieldName } ?? .skip
                if columnMapping[index] == .skip || columnMapping[index] == nil {
                    columnMapping[index] = matched
                }
            }
        } catch {
            // Fall back to keyword autoDetect() already applied
        }
    }

    func buildParsedRows() -> [ParsedPurchaseRow] {
        rows.map { row in
            ParsedPurchaseRow(
                itemName: value(row, .itemName),
                quantityReceived: Double(value(row, .quantity)) ?? 0,
                costPerUnit: Double(value(row, .costPerUnit).replacingOccurrences(
                    of: "[^0-9.]",
                    with: "",
                    options: .regularExpression
                )) ?? 0,
                notes: value(row, .notes)
            )
        }.filter { !$0.itemName.isEmpty }
    }

    private func value(_ row: [String], _ field: PurchaseImportField) -> String {
        guard let col = columnMapping.first(where: { $0.value == field })?.key,
              col < row.count else { return "" }
        return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func autoDetect() {
        let rules: [(PurchaseImportField, [String])] = [
            (.itemName, ["item", "name", "product", "description", "particulars", "goods"]),
            (.quantity, ["qty", "quantity", "count", "units", "pcs", "nos", "pieces", "number"]),
            (.costPerUnit, ["price", "rate", "cost", "unit price", "unit cost", "unit rate", "rate per unit", "basic"]),
            (.notes, ["notes", "remarks", "hsn", "comment", "code"])
        ]
        var used = Set<PurchaseImportField>()
        columnMapping = [:]
        for (i, header) in headers.enumerated() {
            let h = header.lowercased()
            var matched: PurchaseImportField = .skip
            for (field, keywords) in rules where !used.contains(field) {
                if keywords.contains(where: { h == $0 || h.contains($0) || $0.contains(h) }) {
                    matched = field
                    break
                }
            }
            if matched != .skip { used.insert(matched) }
            columnMapping[i] = matched
        }
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var result: [[String]] = []
        var current = ""
        var inQuotes = false
        var row: [String] = []

        for ch in text.unicodeScalars {
            switch ch {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                row.append(current.trimmingCharacters(in: .init(charactersIn: "\r")))
                current = ""
            case "\n", "\r":
                if !inQuotes {
                    row.append(current.trimmingCharacters(in: .init(charactersIn: "\r")))
                    current = ""
                    if row.contains(where: { !$0.isEmpty }) { result.append(row) }
                    row = []
                } else {
                    current.unicodeScalars.append(ch)
                }
            default:
                current.unicodeScalars.append(ch)
            }
        }
        if !row.isEmpty || !current.isEmpty {
            row.append(current)
            if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        }
        return result
    }
}

struct PurchaseInvoiceCSVView: View {
    let defaultStorage: Storage?
    var onCompleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @StateObject private var vm = PurchaseInvoiceCSVViewModel()
    @State private var showFilePicker = false
    @State private var parsedRows: [ParsedPurchaseRow] = []
    @State private var showingReview = false

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case 0: filePickerStep
                case 1: mappingStep
                case 2: previewStep
                default: filePickerStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.step == 0 {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back") { vm.step -= 1 }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.step == 1 {
                        Button("Preview") { vm.step = 2 }
                            .disabled(!vm.canProceedToPreview)
                            .fontWeight(.semibold)
                    } else if vm.step == 2 {
                        Button("Review") {
                            parsedRows = vm.buildParsedRows()
                            showingReview = true
                        }
                        .fontWeight(.semibold)
                        .disabled(vm.buildParsedRows().isEmpty)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .commaSeparatedText,
                UTType(filenameExtension: "csv") ?? .plainText,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(filenameExtension: "xlsm") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.loadFile(from: url)
            }
        }
        .sheet(isPresented: $showingReview) {
            NavigationStack {
                PurchaseReviewView(
                    rows: $parsedRows,
                    defaultStorage: defaultStorage,
                    onConfirm: {
                        showingReview = false
                        onCompleted?() ?? dismiss()
                    },
                    onCancel: { showingReview = false }
                )
                .environmentObject(currencyManager)
            }
            .sheetStyle()
        }
    }

    private var stepTitle: String {
        switch vm.step {
        case 0: return "CSV Invoice"
        case 1: return "Map Columns"
        case 2: return "Preview"
        default: return "CSV Invoice"
        }
    }

    private var filePickerStep: some View {
        Form {
            Section {
                Button { showFilePicker = true } label: {
                    Label("Choose CSV or Excel File", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("Map columns to item name, quantity, and unit cost, then review before saving.")
            }
            if let err = vm.parseError {
                Section {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }
        }
    }

    private var mappingStep: some View {
        List {
            if vm.isSuggestingMappings {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("AI is suggesting column matches…")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Section("\(vm.rows.count) rows · map each column") {
                ForEach(vm.headers.indices, id: \.self) { i in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.headers[i]).fontWeight(.medium).font(.subheadline)
                            if let sample = vm.rows.first, i < sample.count, !sample[i].isEmpty {
                                Text("e.g. \(sample[i])").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.columnMapping[i] ?? .skip },
                            set: { vm.columnMapping[i] = $0 }
                        )) {
                            ForEach(PurchaseImportField.allCases) { field in
                                Text(field.rawValue).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }

    private var previewStep: some View {
        List {
            Section("First \(vm.previewRows.count) rows") {
                ForEach(vm.previewRows.indices, id: \.self) { ri in
                    let row = vm.previewRows[ri]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value(row, .itemName)).fontWeight(.medium)
                        HStack {
                            Text("Qty: \(value(row, .quantity))")
                            Text("Cost: \(value(row, .costPerUnit))")
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func value(_ row: [String], _ field: PurchaseImportField) -> String {
        guard let col = vm.columnMapping.first(where: { $0.value == field })?.key,
              col < row.count else { return "—" }
        return row[col].isEmpty ? "—" : row[col]
    }
}
