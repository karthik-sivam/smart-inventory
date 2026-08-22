import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

// MARK: - Field mapping enum

enum ImportField: String, CaseIterable, Identifiable {
    case name        = "Item Name"
    case quantity    = "Quantity"
    case unitCost    = "Unit Cost"
    case sellingPrice = "Selling Price"
    case category    = "Category"
    case sku         = "SKU"
    case barcode     = "Barcode"
    case minQty      = "Min Quantity"
    case maxQty      = "Max Quantity"
    case storageName = "Storage"
    case notes       = "Notes / Description"
    case uom         = "Unit of Measure"
    case skip        = "— Skip —"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .name:        return "tag"
        case .quantity:    return "number"
        case .unitCost:    return "dollarsign.circle"
        case .sellingPrice: return "tag.circle"
        case .category:    return "folder"
        case .sku:         return "barcode.viewfinder"
        case .barcode:     return "barcode"
        case .minQty:      return "arrow.down.circle"
        case .maxQty:      return "arrow.up.circle"
        case .storageName: return "archivebox"
        case .notes:       return "note.text"
        case .uom:         return "ruler"
        case .skip:        return "xmark"
        }
    }
}

struct ImportResult {
    let imported: Int
    var updated: Int = 0
    let skipped: Int
    let errors: [String]
    var skippedDueToCap: Int = 0
    var skippedDeselected: Int = 0
}

struct BulkPreviewRow: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let name: String
    let quantityLabel: String
    var isUpdate: Bool
    var matchedItemId: UUID?
    var isSelectedForAdd: Bool
    var storageId: UUID
}

// MARK: - ViewModel

@MainActor
final class BulkImportViewModel: ObservableObject {
    @Published var step: Int = 0
    @Published var csvHeaders: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnMapping: [Int: ImportField] = [:]
    @Published var isImporting = false
    @Published var importResult: ImportResult? = nil
    @Published var parseError: String? = nil
    @Published var classifiedRows: [BulkPreviewRow] = []
    @Published var remainingSlotsForPreview: Int = SubscriptionManager.freeItemLimit

    var targetStorage: Storage? = nil
    var importFileExtension: String? = nil
    private var remainingSlotsByStorage: [UUID: Int] = [:]

    var previewRows: [[String]] { Array(rows.prefix(5)) }

    var canProceedToPreview: Bool {
        columnMapping.values.contains(.name) && !rows.isEmpty
    }

    var newRowCount: Int { classifiedRows.filter { !$0.isUpdate }.count }
    var selectedNewCount: Int { classifiedRows.filter { !$0.isUpdate && $0.isSelectedForAdd }.count }
    var updateRowCount: Int { classifiedRows.filter(\.isUpdate).count }

    func remainingSlots(for storageId: UUID) -> Int {
        remainingSlotsByStorage[storageId] ?? remainingSlotsForPreview
    }

    var canImportWithCap: Bool {
        if SubscriptionManager.shared.isPro { return true }
        var selectedByStorage: [UUID: Int] = [:]
        for row in classifiedRows where !row.isUpdate && row.isSelectedForAdd {
            selectedByStorage[row.storageId, default: 0] += 1
        }
        for (sid, count) in selectedByStorage {
            if count > (remainingSlotsByStorage[sid] ?? 0) { return false }
        }
        return updateRowCount > 0 || selectedNewCount > 0
    }

    func prepareCapPreview(
        fallbackStorage: Storage?,
        allStorages: [Storage],
        allItems: [InventoryItem],
        context: ModelContext
    ) {
        guard let fallbackStorage else {
            classifiedRows = []
            return
        }
        let isPro = SubscriptionManager.shared.isPro
        remainingSlotsForPreview = SubscriptionManager.shared.remainingFreeItemSlots(
            storage: fallbackStorage,
            context: context
        )
        remainingSlotsByStorage = [:]

        let nameIdx = columnMapping.first(where: { $0.value == .name })?.key
        let qtyIdx = columnMapping.first(where: { $0.value == .quantity })?.key
        let skuIdx = columnMapping.first(where: { $0.value == .sku })?.key
        let barcodeIdx = columnMapping.first(where: { $0.value == .barcode })?.key
        let storageNameIdx = columnMapping.first(where: { $0.value == .storageName })?.key
        guard let nameCol = nameIdx else {
            classifiedRows = []
            return
        }

        var built: [BulkPreviewRow] = []
        var usedSlots: [UUID: Int] = [:]

        for (index, row) in rows.enumerated() {
            guard nameCol < row.count else { continue }
            let name = row[nameCol].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            func val(_ idx: Int?) -> String? {
                guard let i = idx, i < row.count else { return nil }
                let s = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }

            var itemStorage = fallbackStorage
            if let rawStorage = val(storageNameIdx) {
                let lower = rawStorage.lowercased()
                if let match = allStorages.first(where: {
                    $0.name.lowercased() == lower || $0.name.lowercased().contains(lower)
                }) {
                    itemStorage = match
                }
            }

            if remainingSlotsByStorage[itemStorage.id] == nil {
                remainingSlotsByStorage[itemStorage.id] = SubscriptionManager.shared
                    .remainingFreeItemSlots(storage: itemStorage, context: context)
            }

            let sku = val(skuIdx) ?? ""
            let barcode = val(barcodeIdx) ?? ""
            let matched = Self.matchExisting(
                name: name, sku: sku, barcode: barcode,
                storage: itemStorage, items: allItems
            )
            let qty = val(qtyIdx) ?? ""
            let isUpdate = matched != nil
            var selected = true
            if !isUpdate && !isPro {
                let remaining = remainingSlotsByStorage[itemStorage.id] ?? 0
                let used = usedSlots[itemStorage.id] ?? 0
                if used < remaining {
                    selected = true
                    usedSlots[itemStorage.id] = used + 1
                } else {
                    selected = false
                }
            }

            built.append(BulkPreviewRow(
                rowIndex: index,
                name: name,
                quantityLabel: qty,
                isUpdate: isUpdate,
                matchedItemId: matched?.id,
                isSelectedForAdd: selected,
                storageId: itemStorage.id
            ))
        }
        classifiedRows = built
    }

    private static func matchExisting(
        name: String,
        sku: String,
        barcode: String,
        storage: Storage,
        items: [InventoryItem]
    ) -> InventoryItem? {
        let inStorage = items.filter { $0.storage?.id == storage.id }
        if !barcode.isEmpty, let found = inStorage.first(where: { $0.barcode == barcode }) {
            return found
        }
        if !sku.isEmpty, let found = inStorage.first(where: {
            $0.sku.lowercased() == sku.lowercased()
        }) {
            return found
        }
        let query = name.lowercased()
        return inStorage.first { $0.name.lowercased() == query }
    }

    // MARK: - Load file (dispatches by extension)

    func loadFile(from url: URL) {
        parseError = nil
        let ext = url.pathExtension.lowercased()
        importFileExtension = ext
        if ext == "xlsx" || ext == "xlsm" {
            loadXLSX(from: url)
        } else {
            loadCSV(from: url)
        }
    }

    // MARK: - Parse XLSX (pure Swift — no dependencies)
    // XLSX is a ZIP archive containing XML files.
    // We unzip it into a temp directory, then parse:
    //   xl/sharedStrings.xml  — the string table
    //   xl/worksheets/sheet1.xml — the first sheet's cells

    func loadXLSX(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoqly_import_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            // Copy to tmp (security scoped resource may not be directly unzippable)
            let local = tmp.appendingPathComponent("source.xlsx")
            try FileManager.default.copyItem(at: url, to: local)

            // Unzip using Process (zip utility is always present on iOS simulator / device)
            // On device we use ZipFoundation-free approach: read the ZIP Central Directory ourselves.
            let grid = try XLSXParser.parse(url: local)

            guard grid.count >= 2 else {
                parseError = "The spreadsheet appears empty. Make sure it has a header row and at least one data row."
                return
            }
            let headerIdx = XLSXParser.findHeaderRow(in: grid)
            csvHeaders = grid[headerIdx].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = Array(grid[(headerIdx + 1)...]).filter { $0.contains(where: { !$0.isEmpty }) }
            autoDetect()
            step = 1

        } catch {
            parseError = "Could not read the .xlsx file: \(error.localizedDescription)"
            AnalyticsManager.shared.track(.bulkImportFailed(reason: error.localizedDescription))
        }
    }

    // MARK: - Parse CSV

    func loadCSV(from url: URL) {
        parseError = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let parsed = parseCSV(raw)
            guard parsed.count >= 2 else {
                parseError = "The file has no data rows. Make sure your CSV has a header row and at least one item row."
                return
            }
            csvHeaders = parsed[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = Array(parsed.dropFirst()).filter { $0.contains(where: { !$0.isEmpty }) }
            autoDetect()
            step = 1
        } catch {
            // Try latin1 fallback
            if let raw = try? String(contentsOf: url, encoding: .isoLatin1) {
                let parsed = parseCSV(raw)
                if parsed.count >= 2 {
                    csvHeaders = parsed[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    rows = Array(parsed.dropFirst()).filter { $0.contains(where: { !$0.isEmpty }) }
                    autoDetect()
                    step = 1
                    return
                }
            }
            parseError = "Could not read the file. Please save it as CSV (UTF-8) from Excel or Google Sheets."
            AnalyticsManager.shared.track(.bulkImportFailed(reason: parseError ?? "CSV parse failed"))
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
            case "\n":
                if !inQuotes {
                    row.append(current.trimmingCharacters(in: .init(charactersIn: "\r")))
                    current = ""
                    if row.contains(where: { !$0.isEmpty }) { result.append(row) }
                    row = []
                } else {
                    current.unicodeScalars.append(ch)
                }
            case "\r":
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

    // MARK: - Auto-detect column mapping

    private func autoDetect() {
        let rules: [(ImportField, [String])] = [
            (.name,     ["name", "item name", "product name", "item", "product", "title", "goods"]),
            (.quantity, ["qty", "quantity", "stock", "count", "amount", "units", "current qty",
                         "current stock", "on hand", "on-hand", "stock qty"]),
            (.unitCost, ["cost", "unit cost", "unit price", "unit rate",
                         "rate", "purchase price", "purchase cost"]),
            (.sellingPrice, ["selling price", "sale price", "mrp", "retail price", "price"]),
            (.category, ["category", "cat", "type", "group", "department", "class"]),
            (.sku,      ["sku", "code", "item code", "product code", "part number",
                         "part no", "part#", "ref", "reference", "article"]),
            (.barcode,  ["barcode", "ean", "upc", "gtin", "scan", "scan code"]),
            (.minQty,      ["min", "minimum", "min qty", "min stock", "minimum qty",
                            "reorder point", "reorder level", "reorder"]),
            (.maxQty,      ["max", "maximum", "max qty", "max stock", "maximum qty"]),
            (.storageName, ["storage", "location", "warehouse", "store", "room",
                            "bin", "shelf", "zone", "area", "site"]),
            (.notes,       ["notes", "note", "remark", "remarks", "comment", "comments",
                            "description", "memo"]),
            (.uom,          ["uom", "unit of measure", "unit_of_measure", "unitofmeasure",
                            "measure", "uom symbol", "unit symbol"])
        ]

        var used = Set<ImportField>()
        columnMapping = [:]

        for (i, header) in csvHeaders.enumerated() {
            let h = header.lowercased()
            var matched: ImportField = .skip

            for (field, keywords) in rules {
                guard !used.contains(field) else { continue }
                if keywords.contains(where: { h == $0 || h.contains($0) || $0.contains(h) }) {
                    matched = field
                    break
                }
            }

            columnMapping[i] = matched
            if matched != .skip { used.insert(matched) }
        }
    }

    // MARK: - Import

    func performImport(
        modelContext: ModelContext,
        allStorages: [Storage],
        allUOMs: [UOM],
        allItems: [InventoryItem]
    ) async {
        guard let fallbackStorage = targetStorage else { return }
        isImporting = true

        let nameIdx        = columnMapping.first(where: { $0.value == .name })?.key
        let qtyIdx         = columnMapping.first(where: { $0.value == .quantity })?.key
        let costIdx        = columnMapping.first(where: { $0.value == .unitCost })?.key
        let sellingPriceIdx = columnMapping.first(where: { $0.value == .sellingPrice })?.key
        let catIdx         = columnMapping.first(where: { $0.value == .category })?.key
        let skuIdx         = columnMapping.first(where: { $0.value == .sku })?.key
        let barcodeIdx     = columnMapping.first(where: { $0.value == .barcode })?.key
        let minIdx         = columnMapping.first(where: { $0.value == .minQty })?.key
        let maxIdx         = columnMapping.first(where: { $0.value == .maxQty })?.key
        let storageNameIdx = columnMapping.first(where: { $0.value == .storageName })?.key
        let notesIdx       = columnMapping.first(where: { $0.value == .notes })?.key
        let uomIdx         = columnMapping.first(where: { $0.value == .uom })?.key

        guard let nameCol = nameIdx else {
            importResult = ImportResult(imported: 0, skipped: rows.count,
                                        errors: ["No 'Item Name' column mapped."])
            isImporting = false
            step = 3
            return
        }

        var imported = 0
        var updated = 0
        var skipped = 0
        var skippedDueToCap = 0
        var skippedDeselected = 0
        let errors: [String] = []
        var newItems: [InventoryItem] = []
        var runningCounts: [UUID: Int] = [:]
        let classifiedByIndex = Dictionary(uniqueKeysWithValues: classifiedRows.map { ($0.rowIndex, $0) })

        for (rowIndex, row) in rows.enumerated() {
            guard nameCol < row.count else { skipped += 1; continue }
            let name = row[nameCol].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { skipped += 1; continue }

            func val(_ idx: Int?) -> String? {
                guard let i = idx, i < row.count else { return nil }
                let s = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }

            let qty    = val(qtyIdx).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } ?? 0
            let cost   = val(costIdx).flatMap {
                Double($0.replacingOccurrences(of: ",", with: "")
                         .replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: "₹", with: "")
                         .replacingOccurrences(of: "£", with: "")
                         .replacingOccurrences(of: "€", with: ""))
            } ?? 0
            let minQty = val(minIdx).flatMap { Double($0) } ?? 0
            let maxQty = val(maxIdx).flatMap { Double($0) } ?? 0
            let notes  = val(notesIdx) ?? ""
            let sku    = val(skuIdx) ?? ""
            let barcode = val(barcodeIdx) ?? ""

            var category = "Uncategorised"
            if let rawCat = val(catIdx) {
                let lower = rawCat.lowercased()
                category = InventoryItem.predefinedCategories.first {
                    $0.lowercased() == lower ||
                    $0.lowercased().contains(lower) ||
                    lower.contains($0.lowercased().split(separator: " ").first.map(String.init) ?? "")
                } ?? "Uncategorised"
            }

            // Per-item storage: look up by name from the spreadsheet column, fall back to selected
            var itemStorage = fallbackStorage
            if let rawStorage = val(storageNameIdx) {
                let lower = rawStorage.lowercased()
                if let match = allStorages.first(where: {
                    $0.name.lowercased() == lower || $0.name.lowercased().contains(lower)
                }) {
                    itemStorage = match
                }
            }

            let preview = classifiedByIndex[rowIndex]
            if let preview, preview.isUpdate, let matchId = preview.matchedItemId,
               let existing = allItems.first(where: { $0.id == matchId }) {
                let previous = existing.currentQuantity
                existing.currentQuantity = qty
                if cost > 0 { existing.unitCost = cost }
                if let rawSelling = val(sellingPriceIdx).flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
                    existing.sellingPrice = rawSelling
                }
                if !sku.isEmpty { existing.sku = sku }
                if !barcode.isEmpty { existing.barcode = barcode }
                if minQty > 0 { existing.minQuantity = minQty }
                if maxQty > 0 { existing.maxQuantity = maxQty }
                if category != "Uncategorised" { existing.category = category }
                if !notes.isEmpty { existing.itemDescription = notes }
                existing.updatedAt = Date()
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: itemStorage.name,
                    quantityBefore: previous,
                    quantityAfter: qty,
                    notes: "Updated via bulk import",
                    performedBy: AuthManager.shared.actorName
                )
                modelContext.insert(event)
                FirestoreManager.shared.syncItem(existing)
                updated += 1
                continue
            }

            if let preview, !preview.isUpdate, !preview.isSelectedForAdd, !SubscriptionManager.shared.isPro {
                skippedDeselected += 1
                continue
            }

            let item = InventoryItem(
                name: name,
                description: notes,
                sku: sku,
                barcode: barcode,
                currentQuantity: qty,
                minQuantity: minQty,
                maxQuantity: maxQty,
                unitCost: cost,
                category: category,
                storage: itemStorage,
                uom: nil
            )
            if let rawSelling = val(sellingPriceIdx).flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) {
                item.sellingPrice = rawSelling
            }

            if let rawUOM = val(uomIdx) {
                let lowerRaw = rawUOM.lowercased()
                if let found = allUOMs.first(where: {
                    $0.name.lowercased() == lowerRaw || $0.symbol.lowercased() == lowerRaw
                }) {
                    item.uom = found
                } else {
                    let newUOM = UOM(name: rawUOM, symbol: rawUOM, category: "Count")
                    modelContext.insert(newUOM)
                    item.uom = newUOM
                }
            }

            if !SubscriptionManager.shared.isPro {
                let current = runningCounts[itemStorage.id]
                    ?? SubscriptionManager.shared.itemCount(in: itemStorage, context: modelContext)
                if current >= SubscriptionManager.freeItemLimit {
                    skippedDueToCap += 1
                    continue
                }
                runningCounts[itemStorage.id] = current + 1
            }

            modelContext.insert(item)
            newItems.append(item)
            imported += 1
        }

        // Single save for all items
        modelContext.safeSave(context: "bulkImport \(imported) items")

        // One activity event summarising the import
        if imported > 0 {
            let event = ActivityEvent(
                eventType: "ItemAdded",
                itemName: "Bulk import: \(imported) item\(imported == 1 ? "" : "s")",
                storageName: fallbackStorage.name,
                performedBy: AuthManager.shared.actorName
            )
            modelContext.insert(event)
            modelContext.safeSave(context: "bulkImport activity")
            FirestoreManager.shared.syncActivity(event)
        }

        // Sync each item to Firestore (debounced per item)
        for item in newItems {
            FirestoreManager.shared.syncItem(item)
        }

        importResult = ImportResult(
            imported: imported,
            updated: updated,
            skipped: skipped + skippedDueToCap + skippedDeselected,
            errors: errors,
            skippedDueToCap: skippedDueToCap,
            skippedDeselected: skippedDeselected
        )
        let fmt = (importFileExtension == "xlsx" || importFileExtension == "xlsm") ? "xlsx" : "csv"
        AnalyticsManager.shared.track(.bulkImportCompleted(itemCount: imported, format: fmt))
        AdManager.shared.recordCompletion(event: .bulkImportCompleted)
        isImporting = false
        step = 3
    }

    func valueFor(row: [String], column: Int) -> String {
        guard column < row.count else { return "" }
        return row[column]
    }
}

// MARK: - Main View

struct BulkImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @StateObject private var vm = BulkImportViewModel()
    @State private var showFilePicker = false
    @State private var selectedStorage: Storage? = nil
    @State private var showAddStorage = false
    @State private var showingItemLimitPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case 0:  setupStep
                case 1:  mappingStep
                case 2:  previewStep
                case 3:  resultStep
                default: setupStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.step == 0 {
                        Button("Cancel") { dismiss() }
                    } else if vm.step < 3 {
                        Button("Back") {
                            withAnimation { vm.step -= 1 }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.step == 1 {
                        Button("Preview") {
                            vm.prepareCapPreview(
                                fallbackStorage: selectedStorage ?? vm.targetStorage,
                                allStorages: storages,
                                allItems: allItems,
                                context: modelContext
                            )
                            withAnimation { vm.step = 2 }
                        }
                        .disabled(!vm.canProceedToPreview)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .commaSeparatedText,
                UTType(filenameExtension: "csv")  ?? .plainText,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(filenameExtension: "xlsm") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vm.targetStorage = selectedStorage
                    vm.loadFile(from: url)
                }
            case .failure:
                vm.parseError = "Could not access the file. Please try again."
            }
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView(source: "item_limit", trigger: "item_cap_bulk").sheetStyle()
        }
    }

    private var stepTitle: String {
        switch vm.step {
        case 0: return "Import Items"
        case 1: return "Map Columns"
        case 2: return "Preview"
        case 3: return "Import Complete"
        default: return "Import"
        }
    }

    // MARK: - Step 0: Setup

    private var setupStep: some View {
        Form {
            // Storage picker
            Section {
                if storages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No storages yet.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Button(action: { showAddStorage = true }) {
                            Label("Add Your First Storage", systemImage: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Picker("Storage", selection: $selectedStorage) {
                        Text("Select storage…").tag(Optional<Storage>.none)
                        ForEach(storages, id: \.id) { s in
                            Text(s.name).tag(Optional(s))
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Button(action: { showAddStorage = true }) {
                        Label("Add New Storage", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            } header: {
                Text("Default Storage")
            } footer: {
                Text("Items go here unless your file has a 'Storage' column — in that case each item goes into the storage matching its row value.")
                    .font(.caption)
            }

            // Supported formats tips
            Section(header: Text("Supported formats")) {
                VStack(alignment: .leading, spacing: 10) {
                    tipRow(icon: "tablecells", text: "Excel (.xlsx) — just share the file directly from Excel")
                    tipRow(icon: "tablecells", text: "CSV (.csv) — Excel: File → Save As → CSV (Comma delimited)")
                    tipRow(icon: "globe",      text: "Google Sheets: File → Download → .xlsx or .csv")
                    tipRow(icon: "number",     text: "Numbers: File → Export To → Excel or CSV")
                }
                .padding(.vertical, 4)
            }

            // File picker button
            Section {
                Button(action: {
                    guard selectedStorage != nil else { return }
                    showFilePicker = true
                }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundColor(selectedStorage == nil ? .gray : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose File (CSV or Excel)")
                                .fontWeight(.semibold)
                                .foregroundColor(selectedStorage == nil ? .gray : .blue)
                            Text(selectedStorage == nil
                                 ? "Select a storage above first"
                                 : "Tap to pick a .csv or .xlsx file from Files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(selectedStorage == nil)
            }

            if let err = vm.parseError {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddStorage) {
            AddStorageView(onStorageAdded: { newStorage in
                selectedStorage = newStorage
            })
            .sheetStyle()
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(.blue).frame(width: 20)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Step 1: Column Mapping

    private var mappingStep: some View {
        List {
            Section(header: Text("\(vm.rows.count) rows found · Map each column to a field")) {
                ForEach(vm.csvHeaders.indices, id: \.self) { i in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: vm.columnMapping[i]?.icon ?? "questionmark")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text(vm.csvHeaders[i])
                                    .fontWeight(.medium)
                                    .font(.subheadline)
                            }
                            if let sample = vm.rows.first, i < sample.count, !sample[i].isEmpty {
                                Text("e.g. \(sample[i])")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.columnMapping[i] ?? .skip },
                            set: { vm.columnMapping[i] = $0 }
                        )) {
                            ForEach(ImportField.allCases) { field in
                                Label(field.rawValue, systemImage: field.icon).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.vertical, 4)
                }
            }

            if !vm.canProceedToPreview {
                Section {
                    Label("Map at least 'Item Name' to continue", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Step 2: Preview

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ItemCapReview.shouldShowBanner(
                newCount: vm.newRowCount,
                remainingSlots: vm.remainingSlotsForPreview,
                isPro: SubscriptionManager.shared.isPro
            ) {
                ItemCapOverflowBanner(remainingSlots: vm.remainingSlotsForPreview) {
                    showingItemLimitPaywall = true
                }
            }

            List {
                ForEach($vm.classifiedRows) { $row in
                    HStack(spacing: 10) {
                        if row.isUpdate {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.stoqlyPrimary)
                        } else if !SubscriptionManager.shared.isPro {
                            Button {
                                guard vm.remainingSlots(for: row.storageId) > 0 else { return }
                                row.isSelectedForAdd.toggle()
                            } label: {
                                Image(systemName: row.isSelectedForAdd ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(
                                        vm.remainingSlots(for: row.storageId) == 0
                                        ? .secondary : .stoqlyPrimary
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.remainingSlots(for: row.storageId) == 0)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                if !row.quantityLabel.isEmpty {
                                    Text(row.quantityLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(row.isUpdate
                                     ? L("itemCap.willUpdate", "Will update")
                                     : L("itemCap.willAdd", "Will add"))
                                    .font(.caption2)
                                    .foregroundColor(row.isUpdate ? .stoqlyPrimary : .stoqlySuccess)
                            }
                        }
                    }
                    .opacity(!row.isUpdate && vm.remainingSlots(for: row.storageId) == 0 ? 0.45 : 1)
                }
            }
            .listStyle(.plain)

            Text(
                String(
                    format: L("itemCap.bulk.rowCount", "%1$d of %2$d rows ready"),
                    vm.classifiedRows.count,
                    vm.rows.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)

            if !SubscriptionManager.shared.isPro {
                ItemCapSelectionCounter(
                    selectedNew: vm.selectedNewCount,
                    remainingSlots: vm.remainingSlotsForPreview
                )
                .padding(.horizontal)
                .padding(.top, 6)
            }

            Button(action: {
                Task {
                    await vm.performImport(
                        modelContext: modelContext,
                        allStorages: storages,
                        allUOMs: uoms,
                        allItems: allItems
                    )
                }
            }) {
                HStack {
                    if vm.isImporting {
                        ProgressView().tint(.white)
                        Text("Importing…")
                    } else {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import \(vm.rows.count) Item\(vm.rows.count == 1 ? "" : "s") into \(vm.targetStorage?.name ?? "Storage")")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(vm.canImportWithCap && !vm.isImporting ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(14)
                .fontWeight(.semibold)
            }
            .disabled(vm.isImporting || !vm.canImportWithCap)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Step 3: Result

    private var resultStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if let result = vm.importResult {
                let success = result.imported > 0 || result.updated > 0

                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(success ? .green : .red)

                VStack(spacing: 6) {
                    Text(success ? "Import Complete!" : "Nothing Imported")
                        .font(.title2).fontWeight(.bold)

                    if result.imported > 0 {
                        Text("\(result.imported) item\(result.imported == 1 ? "" : "s") added to \(vm.targetStorage?.name ?? "storage")")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    if result.updated > 0 {
                        Text("\(result.updated) existing item\(result.updated == 1 ? "" : "s") updated")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    if result.skippedDueToCap > 0 {
                        Text("\(result.skippedDueToCap) row\(result.skippedDueToCap == 1 ? "" : "s") skipped — Free limit of 50 items per storage")
                            .font(.caption).foregroundColor(.orange)
                    }
                    if result.skippedDeselected > 0 {
                        Text("\(result.skippedDeselected) row\(result.skippedDeselected == 1 ? "" : "s") skipped (deselected)")
                            .font(.caption).foregroundColor(.orange)
                    }
                    let blankSkipped = result.skipped - result.skippedDueToCap - result.skippedDeselected
                    if blankSkipped > 0 {
                        Text("\(blankSkipped) row\(blankSkipped == 1 ? "" : "s") skipped (missing name or blank)")
                            .font(.caption).foregroundColor(.orange)
                    }
                }

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.errors, id: \.self) { err in
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .fontWeight(.semibold)
            }
            .padding()
        }
    }
}
