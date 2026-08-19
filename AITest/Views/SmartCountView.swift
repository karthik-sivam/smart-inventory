import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - SmartCountView
//
// Entry point shown when user taps "Smart Count" (sparkles icon) from
// StorageDetailView or the Count tab.
//
// Presents four AI-powered input modes as cards:
//   • Voice   — speak items and quantities
//   • Photo   — photograph a single product
//   • Sheet   — photograph a handwritten/printed inventory list
//   • CSV     — upload a spreadsheet with item names and quantities
//
// Free users see remaining uses per mode. Pro users see unlimited.

struct SmartCountView: View {
    var preselectedStorage: Storage? = nil
    var onComplete: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    // @ObservedObject, not @StateObject — AIUsageManager.shared is a pre-existing
    // @MainActor singleton; @StateObject would incorrectly take ownership of it.
    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    @State private var selectedStorage: Storage?
    @State private var showingVoice  = false
    @State private var showingImage  = false
    @State private var showingPaper  = false
    @State private var showingCSV   = false
    @State private var showingPaywall = false
    @AppStorage("stoqly_hasSeenSmartCountTip") private var hasSeenTip = false
    @State private var lastSelectedMode: String?
    @State private var didCompleteSmartCount = false
    @State private var pendingCompletionCount: Int? = nil

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.stoqlyPrimary, .stoqlyAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Smart Count")
                            .font(.title2).fontWeight(.bold)
                        Text("Use AI to take inventory faster — speak, photograph, or upload a sheet. Review everything before it's saved.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal)

                    if !hasSeenTip {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How SmartCount works").font(.subheadline).bold()
                                Text("Photo: point at a shelf to count automatically. Voice: speak your items aloud. Sheet: scan a printed list.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button { hasSeenTip = true } label: {
                                Image(systemName: "xmark").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Storage picker — required before choosing a mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Count into")
                            .font(.subheadline).fontWeight(.semibold)
                        if storages.isEmpty {
                            Text("No storages yet — add one first.")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Picker("Storage", selection: $selectedStorage) {
                                Text("Select storage").tag(Optional<Storage>.none)
                                ForEach(storages) { s in
                                    Text(s.name).tag(Optional(s))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.stoqlyPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.stoqlyCard)
                            .cornerRadius(AppTheme.radiusMd)
                        }
                        if !storages.isEmpty && selectedStorage == nil {
                            Text("Select a storage to enable Smart Count modes.")
                                .font(.caption)
                                .foregroundColor(.stoqlyWarning)
                        }
                    }
                    .padding(.horizontal)

                    // Mode cards
                    modeCard(
                        icon: "mic.fill",
                        iconColor: .stoqlyPrimary,
                        title: "Voice Inventory",
                        description: "Say item names and quantities naturally. \"5 kg of flour, 3 bottles of olive oil…\"",
                        featureType: .voice,
                        action: {
                            lastSelectedMode = "voice"
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "voice"))
                            showingVoice = true
                        }
                    )

                    modeCard(
                        icon: "camera.fill",
                        iconColor: .stoqlyAccent,
                        title: "Photo Inventory",
                        description: "Point your camera at any product. AI identifies it and lets you log the count.",
                        featureType: .image,
                        action: {
                            lastSelectedMode = "photo"
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "photo"))
                            showingImage = true
                        }
                    )

                    modeCard(
                        icon: "doc.text.viewfinder",
                        iconColor: .stoqlyInfo,
                        title: "Sheet Inventory",
                        description: "Photograph a handwritten or printed inventory list. AI extracts all rows for you to review.",
                        featureType: .paper,
                        action: {
                            lastSelectedMode = "sheet"
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "sheet"))
                            showingPaper = true
                        }
                    )

                    modeCard(
                        icon: "tablecells",
                        iconColor: .green,
                        title: "CSV / Excel",
                        description: "Upload a spreadsheet with item names and quantities. AI maps columns — you review before saving.",
                        featureType: .paper,
                        action: {
                            lastSelectedMode = "csv"
                            AnalyticsManager.shared.track(.smartCountModeSelected(mode: "csv"))
                            showingCSV = true
                        }
                    )

                    // Pro upsell if on free tier
                    if !subscriptionManager.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.stoqlyWarning)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Upgrade to Pro for unlimited Smart Count")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("Free tier: 3 uses per feature per month")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Upgrade") { showingPaywall = true }
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.stoqlyWarning)
                        }
                        .padding(14)
                        .background(Color.stoqlyWarningTint)
                        .cornerRadius(AppTheme.radiusMd)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Smart Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if !didCompleteSmartCount {
                            AnalyticsManager.shared.track(.smartCountCancelled(mode: lastSelectedMode))
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedStorage == nil, let preselectedStorage {
                    selectedStorage = preselectedStorage
                }
                AnalyticsManager.shared.track(.smartCountOpened)
            }
        }
        .sheet(isPresented: $showingVoice, onDismiss: { finishSmartCountIfNeeded() }) {
            VoiceInventoryView(
                preselectedStorage: selectedStorage,
                onComplete: { count in
                    didCompleteSmartCount = true
                    pendingCompletionCount = count
                }
            )
            .sheetStyle()
        }
        .sheet(isPresented: $showingImage, onDismiss: { finishSmartCountIfNeeded() }) {
            ImageInventoryView(
                preselectedStorage: selectedStorage,
                onComplete: { count in
                    didCompleteSmartCount = true
                    pendingCompletionCount = count
                }
            )
            .sheetStyle()
        }
        .sheet(isPresented: $showingPaper, onDismiss: { finishSmartCountIfNeeded() }) {
            PaperInventoryView(
                preselectedStorage: selectedStorage,
                onComplete: { count in
                    didCompleteSmartCount = true
                    pendingCompletionCount = count
                }
            )
            .sheetStyle()
        }
        .sheet(isPresented: $showingCSV, onDismiss: { finishSmartCountIfNeeded() }) {
            SmartCountCSVView(
                storage: selectedStorage,
                onComplete: { count in
                    didCompleteSmartCount = true
                    pendingCompletionCount = count
                }
            )
            .sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "ai_limit").sheetStyle()
        }
    }

    private func finishSmartCountIfNeeded() {
        guard let count = pendingCompletionCount else { return }
        pendingCompletionCount = nil
        onComplete?(count)
        dismiss()
    }

    // MARK: - Mode card

    private func modeCard(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        featureType: AIUsageManager.FeatureType,
        action: @escaping () -> Void
    ) -> some View {
        let isPro = subscriptionManager.isPro
        let remaining = usageManager.remaining(featureType, isPro: isPro)
        let canUse = usageManager.canUse(featureType, isPro: isPro)
        let isEnabled = isStorageSelected && canUse

        return Button(action: {
            guard isStorageSelected else { return }
            if !canUse && !isPro {
                AnalyticsManager.shared.track(.proLockTapped(feature: "smart_count_ai"))
                showingPaywall = true
                return
            }
            action()
        }) {
            HStack(spacing: 16) {
                // Icon bubble
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isEnabled ? 0.12 : 0.06))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isEnabled ? iconColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if !isPro {
                        HStack(spacing: 4) {
                            Image(systemName: canUse ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(canUse ? .stoqlySuccess : .stoqlyDanger)
                            Text(
                                canUse
                                    ? String(
                                        format: L("%lld use(s) remaining", "%lld use(s) remaining"),
                                        remaining
                                    )
                                    : L("Limit reached — upgrade to Pro", "Limit reached — upgrade to Pro")
                            )
                                .font(.caption2)
                                .foregroundColor(canUse ? .stoqlySuccess : .stoqlyDanger)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.stoqlyCard)
            .cornerRadius(AppTheme.radiusLg)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isStorageSelected)
    }
}

// MARK: - Smart Count CSV / Excel import

enum CountImportField: String, CaseIterable, Identifiable {
    case itemName = "Item Name"
    case quantity = "Quantity"
    case skip = "— Skip —"

    var id: String { rawValue }
}

struct SmartCountCSVRow: Identifiable {
    let id = UUID()
    let itemName: String
    let quantity: Double
    var matchedItem: InventoryItem?
}

@MainActor
final class SmartCountCSVViewModel: ObservableObject {
    @Published var step = 0
    @Published var headers: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnMapping: [Int: CountImportField] = [:]
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

    func buildParsedRows() -> [SmartCountCSVRow] {
        rows.compactMap { row in
            let name = value(row, .itemName)
            guard !name.isEmpty else { return nil }
            let qty = Double(value(row, .quantity)) ?? 0
            return SmartCountCSVRow(itemName: name, quantity: qty, matchedItem: nil)
        }
    }

    private func value(_ row: [String], _ field: CountImportField) -> String {
        guard let col = columnMapping.first(where: { $0.value == field })?.key,
              col < row.count else { return "" }
        return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoDetect() {
        let rules: [(CountImportField, [String])] = [
            (.itemName, ["item", "name", "product", "description", "particulars", "goods"]),
            (.quantity, ["qty", "quantity", "count", "units", "stock", "amount", "pcs", "nos"])
        ]
        var used = Set<CountImportField>()
        columnMapping = [:]
        for (i, header) in headers.enumerated() {
            let h = header.lowercased()
            var matched: CountImportField = .skip
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

    @MainActor
    private func aiEnhanceMapping() async {
        guard !headers.isEmpty, !rows.isEmpty else { return }
        isSuggestingMappings = true
        defer { isSuggestingMappings = false }
        do {
            let sample = rows.first ?? []
            let suggestions = try await AIInventoryService.shared.suggestCountColumnMapping(headers: headers, sampleRow: sample)
            for (indexStr, fieldName) in suggestions {
                guard let index = Int(indexStr) else { continue }
                let matched = CountImportField.allCases.first { $0.rawValue == fieldName } ?? .skip
                if columnMapping[index] == .skip || columnMapping[index] == nil {
                    columnMapping[index] = matched
                }
            }
        } catch {
            // Fall back to keyword autoDetect() already applied
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

struct SmartCountCSVView: View {
    let storage: Storage?
    var onComplete: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var vm = SmartCountCSVViewModel()
    @State private var showFilePicker = false
    @State private var reviewRows: [SmartCountCSVRow] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case 0: filePickerStep
                case 1: mappingStep
                case 2: previewStep
                case 3: reviewStep
                default: filePickerStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.step == 0 {
                        Button("Cancel") { dismiss() }
                    } else if vm.step < 3 {
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
                            reviewRows = matchRows(vm.buildParsedRows())
                            vm.step = 3
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
    }

    private var stepTitle: String {
        switch vm.step {
        case 0: return "Count Import"
        case 1: return "Map Columns"
        case 2: return "Preview"
        case 3: return "Review Count"
        default: return "Count Import"
        }
    }

    private var filePickerStep: some View {
        Form {
            Section {
                Button { showFilePicker = true } label: {
                    Label("Choose CSV or Excel File", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("Map columns to item name and quantity, then review before saving counts.")
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
                            Text(vm.headers[i].isEmpty ? "Column \(i + 1)" : vm.headers[i])
                                .fontWeight(.medium).font(.subheadline)
                            if let sample = vm.rows.first, i < sample.count, !sample[i].isEmpty {
                                Text("e.g. \(sample[i])").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.columnMapping[i] ?? .skip },
                            set: { vm.columnMapping[i] = $0 }
                        )) {
                            ForEach(CountImportField.allCases) { field in
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
                        Text("Qty: \(value(row, .quantity))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 0) {
            List {
                ForEach(reviewRows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.itemName).font(.subheadline).fontWeight(.medium)
                            if let item = row.matchedItem {
                                Text("→ \(item.name)").font(.caption2).foregroundColor(.stoqlyPrimary)
                            } else {
                                Text("No match in storage").font(.caption2).foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Text(row.quantity.smartFormatted)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                }
            }
            .listStyle(.plain)

            Button(isSaving ? "Saving…" : "Confirm \(matchedReviewRows.count) Item\(matchedReviewRows.count == 1 ? "" : "s")") {
                Task { await saveCounts() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.stoqlyAccent)
            .controlSize(.large)
            .disabled(isSaving || matchedReviewRows.isEmpty)
            .padding()
        }
    }

    private var matchedReviewRows: [SmartCountCSVRow] {
        reviewRows.filter { $0.matchedItem != nil }
    }

    private func value(_ row: [String], _ field: CountImportField) -> String {
        guard let col = vm.columnMapping.first(where: { $0.value == field })?.key,
              col < row.count else { return "—" }
        return row[col].isEmpty ? "—" : row[col]
    }

    private func matchRows(_ rows: [SmartCountCSVRow]) -> [SmartCountCSVRow] {
        let catalog = storage?.items ?? []
        return rows.map { row in
            var updated = row
            let query = row.itemName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = catalog.first(where: { $0.name.lowercased() == query }) {
                updated.matchedItem = exact
            } else if query.count >= 3 {
                let candidates = catalog.filter {
                    $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
                }
                if candidates.count == 1 { updated.matchedItem = candidates.first }
            }
            return updated
        }
    }

    private func saveCounts() async {
        guard let storage else { return }
        isSaving = true
        let actor = AuthManager.shared.actorName
        var savedCount = 0

        for row in matchedReviewRows {
            guard let item = row.matchedItem else { continue }
            let previous = item.currentQuantity
            let count = InventoryCount(
                previousQuantity: previous,
                countedQuantity: row.quantity,
                notes: "CSV import",
                countedBy: actor,
                item: item
            )
            item.countHistory.append(count)
            item.currentQuantity = row.quantity
            item.updatedAt = Date()
            savedCount += 1
            FirestoreManager.shared.syncItem(item)
        }

        if savedCount > 0 {
            let event = ActivityEvent(
                eventType: "BulkCountImported",
                itemName: "\(savedCount) items",
                storageName: storage.name,
                performedBy: actor
            )
            modelContext.insert(event)
            FirestoreManager.shared.syncActivity(event)
        }

        modelContext.safeSave(context: "SmartCountCSVImport")
        AnalyticsManager.shared.track(.smartCountCompleted(mode: "csv", itemCount: savedCount, capturedExtraFields: nil))

        isSaving = false
        onComplete?(savedCount)
        dismiss()
    }
}
