import SwiftUI
import SwiftData
import PhotosUI

// MARK: - PaperInventoryView
//
// Flow:
//   1. User takes photo (or picks from library) of a handwritten or printed
//      inventory sheet — could be a clipboard list, notebook, printed form.
//   2. Image sent to Claude vision — extracts every item row from the sheet.
//   3. Review screen: table of all detected rows; user can edit name/qty/unit
//      or swipe to remove rows.
//   4. Confirm — bulk add/update all rows into the selected storage.
//
// Free limit: 3 uses per calendar month. Pro = unlimited.

struct PaperInventoryView: View {
    var preselectedStorage: Storage? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]

    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    enum Step { case capture, analysing, review, saving }
    @State private var step: Step = .capture

    // Photo
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false

    // Results
    @State private var editableItems: [EditableItem] = []
    @State private var selectedStorage: Storage?

    @State private var errorMessage: String?
    @State private var showingPaywall = false

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .capture:   captureView
                case .analysing: analysingView
                case .review:    reviewView
                case .saving:    savingView
                }
            }
            .navigationTitle("Sheet Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let img = newImage else { return }
            Task { await analyseSheet(img) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await analyseSheet(img)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "ai_limit").sheetStyle()
        }
        .onAppear {
            if selectedStorage == nil, let preselectedStorage {
                selectedStorage = preselectedStorage
            }
        }
    }

    // MARK: - Step 1: Capture

    private var captureView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Usage badge
                if !subscriptionManager.isPro {
                    let remaining = usageManager.remaining(.paper, isPro: false)
                    HStack(spacing: 8) {
                        Image(systemName: "doc.viewfinder")
                            .foregroundColor(.stoqlyPrimary)
                        Text("\(remaining) sheet scan\(remaining == 1 ? "" : "s") left this month")
                            .font(.subheadline)
                        Spacer()
                        Button("Go Pro") { showingPaywall = true }
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.stoqlyPrimary)
                    }
                    .padding(12)
                    .background(Color.stoqlyPrimaryTint)
                    .cornerRadius(10)
                }

                // Storage picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Count into")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
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
                    Text("Select a storage to enable sheet inventory.")
                        .font(.caption)
                        .foregroundColor(.stoqlyWarning)
                }

                // Illustration / instructions
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.stoqlyPrimary, .stoqlyAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 10) {
                        tipRow(icon: "checkmark.circle", "Handwritten clipboards or notebooks")
                        tipRow(icon: "checkmark.circle", "Printed inventory forms or spreadsheets")
                        tipRow(icon: "checkmark.circle", "Take the photo straight — avoid shadows")
                        tipRow(icon: "exclamationmark.triangle", "Very messy handwriting may have lower accuracy")
                    }
                }
                .padding(16)
                .background(Color.stoqlyCard)
                .cornerRadius(AppTheme.radiusLg)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)

                // Capture buttons
                VStack(spacing: 14) {
                    Button {
                        guard usageManager.canUse(.paper, isPro: subscriptionManager.isPro) else {
                            showingPaywall = true; return
                        }
                        showingCamera = true
                    } label: {
                        Label("Photograph Sheet", systemImage: "camera.fill")
                    }
                    .stoqlyButtonStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(!isStorageSelected)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Upload from Library", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.stoqlyPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(AppTheme.radiusMd)
                    }
                    .disabled(!isStorageSelected)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption).foregroundColor(.stoqlyDanger)
                        .padding(10)
                        .background(Color.stoqlyDangerTint)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    // MARK: - Step 2: Analysing

    private var analysingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .cornerRadius(AppTheme.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .stroke(Color.stoqlyPrimary.opacity(0.3), lineWidth: 2)
                    )
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.stoqlyPrimary)
                Text("Reading your sheet…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("This may take a few seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Step 3: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            // Sheet thumbnail strip
            if let image = capturedImage {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .cornerRadius(8)
                        .clipped()

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(editableItems.count) item\(editableItems.count == 1 ? "" : "s") detected")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("Review and edit before saving. Swipe to remove rows.")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        capturedImage = nil
                        editableItems = []
                        step = .capture
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline)
                            .foregroundColor(.stoqlyPrimary)
                    }
                }
                .padding(12)
                .background(Color.stoqlyCard)
            }

            if editableItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text("No items found")
                        .font(.title3).fontWeight(.semibold)
                    Text("The sheet may have been unclear. Try again with better lighting.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        capturedImage = nil
                        editableItems = []
                        step = .capture
                    }
                    .stoqlyButtonStyle()
                    Spacer()
                }
                .padding()
            } else {
                List {
                    Section {
                        ForEach($editableItems) { $item in
                            SheetItemRow(item: $item, selectedStorage: selectedStorage)
                        }
                        .onDelete { editableItems.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text("Detected rows")
                                .font(.caption).fontWeight(.semibold)
                            Spacer()
                            Text("Swipe left to remove")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Button("Re-scan") {
                            capturedImage = nil
                            editableItems = []
                            step = .capture
                        }
                        .font(.subheadline)
                        .foregroundColor(.stoqlyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.stoqlyPrimaryTint)
                        .cornerRadius(AppTheme.radiusMd)

                        Button("Save \(editableItems.count) Item\(editableItems.count == 1 ? "" : "s")") {
                            Task { await saveAll() }
                        }
                        .stoqlyButtonStyle()
                        .frame(maxWidth: .infinity)
                        .disabled(!isStorageSelected)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Step 4: Saving

    private var savingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.stoqlySuccess)
            Text("Saving \(editableItems.count) items…")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func tipRow(icon: String = "checkmark.circle", _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(icon.contains("exclamation") ? .stoqlyWarning : .stoqlyAccent)
                .padding(.top, 1)
            Text(text)
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Logic: Analyse

    private func analyseSheet(_ image: UIImage) async {
        guard usageManager.canUse(.paper, isPro: subscriptionManager.isPro) else {
            await MainActor.run { showingPaywall = true }
            return
        }

        await MainActor.run {
            capturedImage = image
            step = .analysing
            errorMessage = nil
        }

        let compressed = image.jpegData(compressionQuality: 0.75) ?? Data()

        do {
            let items = try await AIInventoryService.shared.parseInventorySheet(imageData: compressed)
            usageManager.recordUse(.paper)

            await MainActor.run {
                editableItems = items.map { EditableItem(from: $0) }
                editableItems.applyNameMatching(in: selectedStorage)
                step = .review
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                AnalyticsManager.shared.track(.smartCountFailed(mode: "sheet", reason: error.localizedDescription))
                step = .capture
            }
        }
    }

    // MARK: - Logic: Save all

    private func saveAll() async {
        guard let storage = selectedStorage else {
            errorMessage = "Please select a storage area."
            return
        }

        step = .saving
        let validItems = editableItems.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        for editable in validItems {
            let matchedUOM = uoms.first { $0.symbol.lowercased() == (editable.unitSymbol?.lowercased() ?? "") }
            let qty = editable.quantity ?? 0

            switch editable.match {
            case .existing(let existing):
                let count = InventoryCount(previousQuantity: existing.currentQuantity, countedQuantity: qty, notes: "Sheet inventory")
                existing.countHistory.append(count)
                existing.currentQuantity = qty
                existing.updatedAt = Date()
            case .new:
                let item = InventoryItem(
                    name: editable.name.trimmingCharacters(in: .whitespaces),
                    currentQuantity: qty,
                    category: editable.category ?? "Uncategorised",
                    storage: storage,
                    uom: matchedUOM
                )
                modelContext.insert(item)
            }
        }

        let event = ActivityEvent(
            eventType: "BulkImportCompleted",
            itemName: "\(validItems.count) items",
            storageName: storage.name,
            notes: "Added via sheet/paper inventory",
            performedBy: "You"
        )
        modelContext.insert(event)
        modelContext.safeSave(context: "PaperInventorySave")

        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "sheet",
            itemCount: validItems.count
        ))

        Task {
            for item in storage.items {
                FirestoreManager.shared.syncItem(item)
            }
        }

        dismiss()
    }
}

// MARK: - SheetItemRow

private struct SheetItemRow: View {
    @Binding var item: EditableItem
    var selectedStorage: Storage?

    var body: some View {
        HStack(spacing: 10) {
            // Low-confidence indicator
            if item.confidence < 0.75 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.stoqlyWarning)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Item name", text: $item.name)
                    .font(.subheadline).fontWeight(.medium)

                ItemMatchReviewControls(
                    match: $item.match,
                    parsedName: item.name,
                    selectedStorage: selectedStorage
                )

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Qty:")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $item.quantity, format: .number)
                            .font(.caption)
                            .keyboardType(.decimalPad)
                            .frame(width: 55)
                    }
                    HStack(spacing: 4) {
                        Text("Unit:")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("pcs", text: Binding(
                            get: { item.unitSymbol ?? "" },
                            set: { item.unitSymbol = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.caption)
                        .frame(width: 40)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
