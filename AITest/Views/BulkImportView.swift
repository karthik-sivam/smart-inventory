import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation
import zlib

// MARK: - Field mapping enum

enum ImportField: String, CaseIterable, Identifiable {
    case name        = "Item Name"
    case quantity    = "Quantity"
    case unitCost    = "Unit Cost"
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
    let skipped: Int
    let errors: [String]
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

    var targetStorage: Storage? = nil
    var importFileExtension: String? = nil

    var previewRows: [[String]] { Array(rows.prefix(5)) }

    var canProceedToPreview: Bool {
        columnMapping.values.contains(.name) && !rows.isEmpty
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
            let grid = try parseXLSXFile(at: local)

            guard grid.count >= 2 else {
                parseError = "The spreadsheet appears empty. Make sure it has a header row and at least one data row."
                return
            }
            csvHeaders = grid[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = Array(grid.dropFirst()).filter { $0.contains(where: { !$0.isEmpty }) }
            autoDetect()
            step = 1

        } catch {
            parseError = "Could not read the .xlsx file: \(error.localizedDescription)"
            AnalyticsManager.shared.track(.bulkImportFailed(reason: error.localizedDescription))
        }
    }

    // Parses an XLSX file at `path` into a 2-D String array (rows × columns).
    // Uses only Foundation — reads the ZIP entries manually.
    private func parseXLSXFile(at url: URL) throws -> [[String]] {
        let data = try Data(contentsOf: url)

        // ---- locate ZIP entries ----
        guard let entries = zipEntries(in: data) else {
            throw NSError(domain: "XLSXParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid ZIP/XLSX file"])
        }

        // Shared strings table (may not exist if all cells are numbers/dates)
        var sharedStrings: [String] = []
        if let ssData = entries["xl/sharedStrings.xml"] {
            sharedStrings = parseSharedStrings(xml: ssData)
        }

        // First worksheet
        let sheetKey = entries.keys.first(where: {
            $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml")
        }) ?? "xl/worksheets/sheet1.xml"

        guard let sheetData = entries[sheetKey] else {
            throw NSError(domain: "XLSXParser", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Worksheet not found in file"])
        }

        return parseSheet(xml: sheetData, sharedStrings: sharedStrings)
    }

    // ---- ZIP reader (no dependencies) ----
    private func zipEntries(in data: Data) -> [String: Data]? {
        // Locate End of Central Directory record (signature 0x06054b50)
        let eocdSig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard let eocdOffset = data.range(of: Data(eocdSig), options: .backwards)?.lowerBound else { return nil }
        guard eocdOffset + 22 <= data.count else { return nil }

        let centralDirOffset = Int(data.uint32LE(at: eocdOffset + 16))
        let centralDirSize   = Int(data.uint32LE(at: eocdOffset + 12))
        guard centralDirOffset + centralDirSize <= data.count else { return nil }

        var result: [String: Data] = [:]
        let cdsig: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        var pos = centralDirOffset

        while pos + 46 <= centralDirOffset + centralDirSize {
            guard data[pos..<pos+4].elementsEqual(cdsig) else { break }
            let fileNameLen   = Int(data.uint16LE(at: pos + 28))
            let extraLen      = Int(data.uint16LE(at: pos + 30))
            let commentLen    = Int(data.uint16LE(at: pos + 32))
            let localOffset   = Int(data.uint32LE(at: pos + 42))
            let nameBytes     = data[pos+46..<pos+46+fileNameLen]
            let name          = String(bytes: nameBytes, encoding: .utf8) ?? ""

            // Read local file header at localOffset to get actual data
            let lhPos = localOffset
            guard lhPos + 30 <= data.count else { pos += 46 + fileNameLen + extraLen + commentLen; continue }
            let lhFileNameLen = Int(data.uint16LE(at: lhPos + 26))
            let lhExtraLen    = Int(data.uint16LE(at: lhPos + 28))
            let compMethod    = Int(data.uint16LE(at: lhPos + 8))
            let compSize      = Int(data.uint32LE(at: lhPos + 18))
            let uncompSize    = Int(data.uint32LE(at: lhPos + 22))
            let dataStart     = lhPos + 30 + lhFileNameLen + lhExtraLen

            guard dataStart + compSize <= data.count else { pos += 46 + fileNameLen + extraLen + commentLen; continue }

            let compData = data[dataStart..<dataStart+compSize]
            if compMethod == 0 {
                // Stored (no compression)
                result[name] = Data(compData)
            } else if compMethod == 8 {
                // Deflate — use zlib via NSData
                if let inflated = inflateDeflate(Data(compData), expectedSize: uncompSize) {
                    result[name] = inflated
                }
            }
            pos += 46 + fileNameLen + extraLen + commentLen
        }
        return result
    }

    // Decompress raw DEFLATE data (as stored in ZIP/XLSX files) using
    // the system zlib with windowBits = -15 (raw deflate, no header/trailer).
    private func inflateDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        return compressed.withUnsafeBytes { (srcBuf: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcBuf.baseAddress else { return nil }

            var strm = z_stream()
            strm.next_in  = UnsafeMutablePointer<UInt8>(
                mutating: srcBase.assumingMemoryBound(to: UInt8.self))
            strm.avail_in = UInt32(compressed.count)

            // -15 → raw DEFLATE (ZIP format, no zlib header/trailer)
            let initStatus = inflateInit2_(
                &strm, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else { return nil }
            defer { inflateEnd(&strm) }

            var output = Data()
            let chunkSize = max(expectedSize > 0 ? expectedSize : 0, 65536)
            var chunk = Data(count: chunkSize)
            var status: Int32 = Z_OK

            repeat {
                let produced: Int = chunk.withUnsafeMutableBytes { dstBuf -> Int in
                    guard let dst = dstBuf.baseAddress else { return 0 }
                    strm.next_out  = dst.assumingMemoryBound(to: UInt8.self)
                    strm.avail_out = UInt32(chunkSize)
                    status = inflate(&strm, Z_FINISH)
                    return chunkSize - Int(strm.avail_out)
                }
                if produced > 0 { output.append(chunk.prefix(produced)) }
            } while status == Z_OK  // Z_OK = more output available; Z_STREAM_END = done

            return status == Z_STREAM_END ? output : nil
        }
    }

    // ---- Shared Strings XML parser ----
    private func parseSharedStrings(xml: Data) -> [String] {
        // Minimal SAX-style parse: extract all <t>...</t> values, grouped by <si>
        guard let text = String(data: xml, encoding: .utf8) else { return [] }
        var strings: [String] = []
        var current = ""
        var inT = false
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "<" {
                let tagStart = i
                while i < text.endIndex && text[i] != ">" { text.formIndex(after: &i) }
                if i < text.endIndex { text.formIndex(after: &i) }
                let tag = String(text[tagStart..<i])
                let tagName = tag.dropFirst().prefix(while: { !$0.isWhitespace && $0 != "/" && $0 != ">" })

                if tagName == "si" && !tag.hasPrefix("</") {
                    current = ""
                } else if tagName == "t" && !tag.hasPrefix("</") {
                    inT = true
                } else if tagName == "/t" || tag == "</t>" {
                    inT = false
                } else if tagName == "/si" || tag == "</si>" {
                    strings.append(current)
                }
            } else if inT {
                current.append(text[i])
                text.formIndex(after: &i)
            } else {
                text.formIndex(after: &i)
            }
        }
        return strings
    }

    // ---- Sheet XML parser ----
    private func parseSheet(xml: Data, sharedStrings: [String]) -> [[String]] {
        guard let text = String(data: xml, encoding: .utf8) else { return [] }

        // Maps Excel column letters to 0-based index
        func colIndex(_ ref: String) -> Int {
            var idx = 0
            for ch in ref.unicodeScalars {
                if ch.value >= 65 && ch.value <= 90 { // A-Z
                    idx = idx * 26 + Int(ch.value - 64)
                } else { break }
            }
            return idx - 1
        }

        func rowIndex(_ ref: String) -> Int {
            let digits = ref.drop(while: { !$0.isNumber })
            return (Int(digits) ?? 1) - 1
        }

        // Collect all cells: (row, col, value)
        var cells: [(row: Int, col: Int, value: String)] = []
        var maxRow = 0, maxCol = 0

        // Simple regex-free parse: find <c r="A1" t="s">...<v>...</v>
        var i = text.startIndex
        while i < text.endIndex {
            // Find next <c
            guard let cOpen = text.range(of: "<c ", range: i..<text.endIndex) else { break }
            guard let tagClose = text.range(of: ">", range: cOpen.lowerBound..<text.endIndex) else { break }

            let cTag = String(text[cOpen.lowerBound..<tagClose.upperBound])

            // Extract r="..." attribute
            var cellRef = ""
            if let rRange = cTag.range(of: "r=\"") {
                let afterR = cTag.index(rRange.upperBound, offsetBy: 0)
                if let endQ = cTag.range(of: "\"", range: afterR..<cTag.endIndex) {
                    cellRef = String(cTag[afterR..<endQ.lowerBound])
                }
            }

            // Extract t="..." attribute (type: s=shared string, otherwise numeric/date)
            var cellType = ""
            if let tRange = cTag.range(of: " t=\"") {
                let afterT = tRange.upperBound
                if let endQ = cTag.range(of: "\"", range: afterT..<cTag.endIndex) {
                    cellType = String(cTag[afterT..<endQ.lowerBound])
                }
            }

            // Self-closing <c .../> — no value
            if cTag.hasSuffix("/>") { i = tagClose.upperBound; continue }

            // Find </c>
            guard let cClose = text.range(of: "</c>", range: tagClose.upperBound..<text.endIndex) else {
                i = tagClose.upperBound; continue
            }

            let cellContent = String(text[tagClose.upperBound..<cClose.lowerBound])

            // Extract <v>...</v>
            var rawValue = ""
            if let vOpen = cellContent.range(of: "<v>"),
               let vClose = cellContent.range(of: "</v>") {
                rawValue = String(cellContent[vOpen.upperBound..<vClose.lowerBound])
            } else if let isOpen = cellContent.range(of: "<is>"),
                      let tOpen = cellContent.range(of: "<t>", range: isOpen.upperBound..<cellContent.endIndex),
                      let tClose = cellContent.range(of: "</t>", range: tOpen.upperBound..<cellContent.endIndex) {
                rawValue = String(cellContent[tOpen.upperBound..<tClose.lowerBound])
            }

            // Decode value
            var value: String
            if cellType == "s", let idx = Int(rawValue), idx < sharedStrings.count {
                value = sharedStrings[idx]
            } else {
                value = rawValue
            }
            value = value
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;",  with: "<")
                .replacingOccurrences(of: "&gt;",  with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")

            if !cellRef.isEmpty {
                let col = colIndex(cellRef.prefix(while: { $0.isLetter }).description)
                let row = rowIndex(cellRef)
                cells.append((row: row, col: col, value: value))
                maxRow = max(maxRow, row)
                maxCol = max(maxCol, col)
            }

            i = cClose.upperBound
        }

        guard !cells.isEmpty else { return [] }

        // Build 2-D grid
        var grid = Array(repeating: Array(repeating: "", count: maxCol + 1), count: maxRow + 1)
        for cell in cells {
            grid[cell.row][cell.col] = cell.value
        }
        return grid
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
            (.unitCost, ["price", "cost", "unit cost", "unit price", "unit rate",
                         "rate", "selling price", "purchase price", "value"]),
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

    func performImport(modelContext: ModelContext, allStorages: [Storage], allUOMs: [UOM]) async {
        guard let fallbackStorage = targetStorage else { return }
        isImporting = true

        let nameIdx        = columnMapping.first(where: { $0.value == .name })?.key
        let qtyIdx         = columnMapping.first(where: { $0.value == .quantity })?.key
        let costIdx        = columnMapping.first(where: { $0.value == .unitCost })?.key
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
        var skipped = 0
        var errors: [String] = []
        var newItems: [InventoryItem] = []

        for row in rows {
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

        importResult = ImportResult(imported: imported, skipped: skipped, errors: errors)
        let fmt = (importFileExtension == "xlsx" || importFileExtension == "xlsm") ? "xlsx" : "csv"
        AnalyticsManager.shared.track(.bulkImportCompleted(itemCount: imported, format: fmt))
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

    @StateObject private var vm = BulkImportViewModel()
    @State private var showFilePicker = false
    @State private var selectedStorage: Storage? = nil
    @State private var showAddStorage = false

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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: vm.columnMapping[i]?.icon ?? "questionmark")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text(vm.csvHeaders[i])
                                .fontWeight(.medium)
                            Spacer()
                        }

                        // Sample value from first row
                        if let sample = vm.rows.first, i < sample.count, !sample[i].isEmpty {
                            Text("e.g. \(sample[i])")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

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
            // Column headers
            let mappedCols = vm.csvHeaders.indices.filter {
                (vm.columnMapping[$0] ?? .skip) != .skip
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(mappedCols, id: \.self) { i in
                            Text(vm.columnMapping[i]?.rawValue ?? vm.csvHeaders[i])
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .frame(width: 110, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(Color(.systemGroupedBackground))

                    Divider()

                    // Data rows
                    ForEach(vm.previewRows.indices, id: \.self) { ri in
                        HStack(spacing: 0) {
                            ForEach(mappedCols, id: \.self) { ci in
                                Text(ci < vm.previewRows[ri].count ? vm.previewRows[ri][ci] : "")
                                    .font(.caption)
                                    .frame(width: 110, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .lineLimit(1)
                            }
                        }
                        .background(ri % 2 == 0 ? Color(.systemBackground) : Color(.systemGroupedBackground))
                        Divider()
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.06), radius: 4)
            .padding()

            Text("Showing first \(vm.previewRows.count) of \(vm.rows.count) rows")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            // Import button
            Button(action: {
                Task {
                    await vm.performImport(modelContext: modelContext, allStorages: storages, allUOMs: uoms)
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
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
                .fontWeight(.semibold)
            }
            .disabled(vm.isImporting)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Step 3: Result

    private var resultStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if let result = vm.importResult {
                let success = result.imported > 0

                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(success ? .green : .red)

                VStack(spacing: 6) {
                    Text(success ? "Import Complete!" : "Nothing Imported")
                        .font(.title2).fontWeight(.bold)

                    if success {
                        Text("\(result.imported) item\(result.imported == 1 ? "" : "s") added to \(vm.targetStorage?.name ?? "storage")")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    if result.skipped > 0 {
                        Text("\(result.skipped) row\(result.skipped == 1 ? "" : "s") skipped (missing name or blank)")
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

// MARK: - Data helpers for ZIP parsing

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }
}
