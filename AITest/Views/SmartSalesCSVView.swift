import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum SalesImportField: String, CaseIterable, Identifiable {
    case itemName = "Item Name"
    case quantity = "Quantity"
    case pricePerUnit = "Price Per Unit"
    case date = "Date"
    case notes = "Notes"
    case skip = "— Skip —"

    var id: String { rawValue }
}

@MainActor
final class SmartSalesCSVViewModel: ObservableObject {
    @Published var step = 0
    @Published var headers: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnMapping: [Int: SalesImportField] = [:]
    @Published var parseError: String?

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
            headers = grid[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = Array(grid.dropFirst()).filter { $0.contains(where: { !$0.isEmpty }) }
            autoDetect()
            step = 1
        } catch {
            parseError = "Could not read file: \(error.localizedDescription)"
        }
    }

    func buildParsedRows() -> [ParsedSaleRow] {
        rows.map { row in
            ParsedSaleRow(
                itemName: value(row, .itemName),
                quantitySold: Double(value(row, .quantity)) ?? 0,
                pricePerUnit: Double(value(row, .pricePerUnit)) ?? 0,
                notes: value(row, .notes)
            )
        }.filter { !$0.itemName.isEmpty }
    }

    private func value(_ row: [String], _ field: SalesImportField) -> String {
        guard let col = columnMapping.first(where: { $0.value == field })?.key, col < row.count else { return "" }
        return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoDetect() {
        let rules: [(SalesImportField, [String])] = [
            (.itemName, ["item", "name", "product", "description"]),
            (.quantity, ["qty", "quantity", "count", "units"]),
            (.pricePerUnit, ["price", "rate", "unit price", "selling price", "amount"]),
            (.date, ["date", "time", "when"]),
            (.notes, ["notes", "remarks", "comment"])
        ]
        var used = Set<SalesImportField>()
        columnMapping = [:]
        for (i, header) in headers.enumerated() {
            let h = header.lowercased()
            var matched: SalesImportField = .skip
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

struct SmartSalesCSVView: View {
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager

    @StateObject private var vm = SmartSalesCSVViewModel()
    @State private var showFilePicker = false
    @State private var parsedRows: [ParsedSaleRow] = []
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
                        Button("Review Sales") {
                            parsedRows = vm.buildParsedRows()
                            AnalyticsManager.shared.track(.smartSalesModeSelected(mode: "csv"))
                            showingReview = true
                        }
                        .fontWeight(.semibold)
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
                SaleEntryReviewView(
                    rows: $parsedRows,
                    onConfirm: { onCompleted?() ?? dismiss() },
                    onCancel: { showingReview = false }
                )
                .environmentObject(currencyManager)
            }
            .sheetStyle()
        }
    }

    private var stepTitle: String {
        switch vm.step {
        case 0: return "Import Sales File"
        case 1: return "Map Columns"
        case 2: return "Preview"
        default: return "Import Sales"
        }
    }

    private var filePickerStep: some View {
        Form {
            Section {
                Button { showFilePicker = true } label: {
                    Label("Choose CSV or Excel File", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("Map columns to item name, quantity, and price, then review before saving.")
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
            Section("\(vm.rows.count) rows · map each column") {
                ForEach(vm.headers.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.headers[i]).fontWeight(.medium)
                        if let sample = vm.rows.first, i < sample.count, !sample[i].isEmpty {
                            Text("e.g. \(sample[i])").font(.caption).foregroundColor(.secondary)
                        }
                        Picker("Field", selection: Binding(
                            get: { vm.columnMapping[i] ?? .skip },
                            set: { vm.columnMapping[i] = $0 }
                        )) {
                            ForEach(SalesImportField.allCases) { field in
                                Text(field.rawValue).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
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
                            Text("Price: \(value(row, .pricePerUnit))")
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func value(_ row: [String], _ field: SalesImportField) -> String {
        guard let col = vm.columnMapping.first(where: { $0.value == field })?.key, col < row.count else { return "—" }
        return row[col].isEmpty ? "—" : row[col]
    }
}
