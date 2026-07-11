import Foundation
import zlib

struct XLSXParser {
    static func parse(url: URL) throws -> [[String]] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> [[String]] {
        guard let entries = zipEntries(in: data) else {
            throw NSError(domain: "XLSXParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid ZIP/XLSX file"])
        }

        var sharedStrings: [String] = []
        let ssKey = entries.keys.first(where: { $0.lowercased() == "xl/sharedstrings.xml" })
        if let ssKey, let ssData = entries[ssKey] {
            sharedStrings = parseSharedStrings(xml: ssData)
        }

        let sheetKey = entries.keys.first(where: {
            $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml")
        }) ?? "xl/worksheets/sheet1.xml"

        guard let sheetData = entries[sheetKey] else {
            throw NSError(domain: "XLSXParser", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Worksheet not found in file"])
        }

        return parseSheet(xml: sheetData, sharedStrings: sharedStrings)
    }

    private static func zipEntries(in data: Data) -> [String: Data]? {
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
                result[name] = Data(compData)
            } else if compMethod == 8 {
                if let inflated = inflateDeflate(Data(compData), expectedSize: uncompSize) {
                    result[name] = inflated
                }
            }
            pos += 46 + fileNameLen + extraLen + commentLen
        }
        return result
    }

    private static func inflateDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        return compressed.withUnsafeBytes { (srcBuf: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcBuf.baseAddress else { return nil }

            var strm = z_stream()
            strm.next_in  = UnsafeMutablePointer<UInt8>(
                mutating: srcBase.assumingMemoryBound(to: UInt8.self))
            strm.avail_in = UInt32(compressed.count)

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
            } while status == Z_OK

            return status == Z_STREAM_END ? output : nil
        }
    }

    private static func parseSharedStrings(xml: Data) -> [String] {
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
                    strings.append(decodeEntities(current))
                    current = ""
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

    private static func parseSheet(xml: Data, sharedStrings: [String]) -> [[String]] {
        guard let text = String(data: xml, encoding: .utf8) else { return [] }

        func colIndex(_ ref: String) -> Int {
            var idx = 0
            for ch in ref.unicodeScalars {
                if ch.value >= 65 && ch.value <= 90 {
                    idx = idx * 26 + Int(ch.value - 64)
                } else { break }
            }
            return idx - 1
        }

        func rowIndex(_ ref: String) -> Int {
            let digits = ref.drop(while: { !$0.isNumber })
            return (Int(digits) ?? 1) - 1
        }

        var cells: [(row: Int, col: Int, value: String)] = []
        var maxRow = 0, maxCol = 0

        var i = text.startIndex
        while i < text.endIndex {
            guard let cOpen = text.range(of: "<c ", range: i..<text.endIndex) else { break }
            guard let tagClose = text.range(of: ">", range: cOpen.lowerBound..<text.endIndex) else { break }

            let cTag = String(text[cOpen.lowerBound..<tagClose.upperBound])

            var cellRef = ""
            if let rRange = cTag.range(of: "r=\"") {
                let afterR = cTag.index(rRange.upperBound, offsetBy: 0)
                if let endQ = cTag.range(of: "\"", range: afterR..<cTag.endIndex) {
                    cellRef = String(cTag[afterR..<endQ.lowerBound])
                }
            }

            var cellType = ""
            if let tRange = cTag.range(of: " t=\"") {
                let afterT = tRange.upperBound
                if let endQ = cTag.range(of: "\"", range: afterT..<cTag.endIndex) {
                    cellType = String(cTag[afterT..<endQ.lowerBound])
                }
            }

            if cTag.hasSuffix("/>") { i = tagClose.upperBound; continue }

            guard let cClose = text.range(of: "</c>", range: tagClose.upperBound..<text.endIndex) else {
                i = tagClose.upperBound; continue
            }

            let cellContent = String(text[tagClose.upperBound..<cClose.lowerBound])

            var rawValue = ""
            if let vOpen = cellContent.range(of: "<v>"),
               let vClose = cellContent.range(of: "</v>") {
                rawValue = String(cellContent[vOpen.upperBound..<vClose.lowerBound])
            } else if let isOpen = cellContent.range(of: "<is>"),
                      let tOpen = cellContent.range(of: "<t>", range: isOpen.upperBound..<cellContent.endIndex),
                      let tClose = cellContent.range(of: "</t>", range: tOpen.upperBound..<cellContent.endIndex) {
                rawValue = String(cellContent[tOpen.upperBound..<tClose.lowerBound])
            }

            var value: String
            if cellType == "s", let idx = Int(rawValue), idx < sharedStrings.count {
                value = sharedStrings[idx]
            } else {
                value = rawValue
            }
            value = decodeEntities(value)

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

        var grid = Array(repeating: Array(repeating: "", count: maxCol + 1), count: maxRow + 1)
        for cell in cells {
            grid[cell.row][cell.col] = cell.value
        }
        return grid
    }

    // MARK: - Smart header-row detection

    /// Scans the first 15 rows and returns the index of the row with the most non-empty cells.
    /// Ties go to the earlier row.  Handles the common pattern where row 1 is a title/metadata
    /// line and the actual column headers sit in row 3 or 4.
    static func findHeaderRow(in grid: [[String]]) -> Int {
        let searchCount = min(15, grid.count)
        var bestRow = 0
        var bestCount = 0
        for idx in 0..<searchCount {
            let nonEmpty = grid[idx].filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            if nonEmpty > bestCount {
                bestCount = nonEmpty
                bestRow = idx
            }
        }
        return bestRow
    }

    // MARK: - XML entity decoder

    /// Decodes standard XML named entities and numeric character references (&#NNN; and &#xHHH;).
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex

        while i < input.endIndex {
            let ch = input[i]
            guard ch == "&" else {
                result.append(ch)
                i = input.index(after: i)
                continue
            }
            // Search for closing semicolon within next 12 characters
            let searchEnd = input.index(i, offsetBy: 12, limitedBy: input.endIndex) ?? input.endIndex
            if let semiRange = input.range(of: ";", range: i..<searchEnd) {
                let entity = String(input[input.index(after: i)..<semiRange.lowerBound])
                var decoded: String? = nil

                switch entity {
                case "amp":         decoded = "&"
                case "lt":          decoded = "<"
                case "gt":          decoded = ">"
                case "quot":        decoded = "\""
                case "apos", "#39": decoded = "'"
                case "nbsp":        decoded = "\u{00A0}"
                default:
                    if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                        if let cp = UInt32(entity.dropFirst(2), radix: 16),
                           let scalar = Unicode.Scalar(cp) {
                            decoded = String(Character(scalar))
                        }
                    } else if entity.hasPrefix("#") {
                        if let cp = UInt32(entity.dropFirst()),
                           let scalar = Unicode.Scalar(cp) {
                            decoded = String(Character(scalar))
                        }
                    }
                }

                if let d = decoded {
                    result += d
                    i = semiRange.upperBound
                    continue
                }
            }
            result.append(ch)
            i = input.index(after: i)
        }
        return result
    }
}

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
