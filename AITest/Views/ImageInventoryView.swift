import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ImageInventoryView
//
// Flow:
//   1. User takes photo or picks from library
//   2. Image compressed and sent to Claude vision
//   3. Claude returns ALL products visible — single item OR whole shelf scan
//   4. Review screen:
//        • Single product → editable form (qty pre-filled, existing-item match check)
//        • Multiple products → editable list, identical to Voice Inventory review
//   5. Save — updates existing item counts or adds new items
//
// Free limit: 3 uses per calendar month. Pro = unlimited.

struct ImageInventoryView: View {
    var preselectedStorage: Storage? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]

    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    enum Step { case capture, analysing, review, saving }
    @State private var step: Step = .capture

    // Photo capture
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false

    // Multi-product results (shelf scan — any count including 1)
    @State private var parsedItems: [EditableItem] = []

    // Single-product form fields (used when exactly 1 product found)
    @State private var parsedItem: ParsedInventoryItem?
    @State private var matchedExistingItem: InventoryItem?
    @State private var editableName       = ""
    @State private var editableQty        = ""
    @State private var editableUnit       = ""
    @State private var editableCategory   = "Uncategorised"
    @State private var selectedStorage: Storage?

    @State private var errorMessage: String?
    @State private var showingPaywall = false

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    /// Shelf-scan mode: AI returned more than one distinct product type.
    private var isShelfScan: Bool { parsedItems.count > 1 }

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
            .navigationTitle("Photo Inventory")
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
            Task { await analyseImage(img) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await analyseImage(img)
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
                    let remaining = usageManager.remaining(.image, isPro: false)
                    HStack(spacing: 8) {
                        Image(systemName: "camera.badge.plus")
                            .foregroundColor(.stoqlyPrimary)
                        Text("\(remaining) photo scan\(remaining == 1 ? "" : "s") left this month")
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

                storagePickerSection

                VStack(alignment: .leading, spacing: 8) {
                    Label("Works for single items and full shelves", systemImage: "lightbulb")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.stoqlyAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        tipRow("Point at one product — AI identifies it and counts visible units")
                        tipRow("Photograph a whole shelf — AI lists every product found")
                        tipRow("Packaging, labels, and barcodes all work")
                    }
                }
                .padding(12)
                .background(Color.stoqlyAccentTint)
                .cornerRadius(10)

                VStack(spacing: 14) {
                    Button {
                        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
                            showingPaywall = true
                            return
                        }
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .stoqlyButtonStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(!isStorageSelected)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.stoqlyPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(AppTheme.radiusMd)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
                            showingPaywall = true
                            return
                        }
                    })
                    .disabled(!isStorageSelected)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.stoqlyDanger)
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
        VStack(spacing: 20) {
            Spacer()
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(AppTheme.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .stroke(Color.stoqlyPrimary.opacity(0.3), lineWidth: 2)
                    )
                    .padding(.horizontal)
            }
            ProgressView()
                .scaleEffect(1.3)
                .tint(.stoqlyPrimary)
            Text("Scanning for products…")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Step 3: Review

    @ViewBuilder
    private var reviewView: some View {
        if isShelfScan {
            shelfScanReviewView
        } else {
            singleItemReviewView
        }
    }

    // ── Single product ──────────────────────────────────────────────────────

    private var singleItemReviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photo thumbnail + match status
                if let image = capturedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(AppTheme.radiusMd)
                            .clipped()

                        VStack(alignment: .leading, spacing: 4) {
                            if let existing = matchedExistingItem {
                                Label("Matched to existing item", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundColor(.stoqlySuccess)
                                Text("Current stock: \(existing.currentQuantity.smartFormatted) \(existing.uom?.symbol ?? "")")
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Label("New item detected", systemImage: "plus.circle.fill")
                                    .font(.caption).foregroundColor(.stoqlyPrimary)
                                Text("Will be added to your inventory")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.stoqlyCard)
                    .cornerRadius(AppTheme.radiusMd)
                }

                VStack(spacing: 16) {
                    formField(label: "Product Name") {
                        TextField("Enter name", text: $editableName)
                    }

                    HStack(spacing: 12) {
                        formField(label: "Quantity") {
                            TextField("0", text: $editableQty)
                                .keyboardType(.decimalPad)
                        }
                        formField(label: "Unit") {
                            TextField("pcs", text: $editableUnit)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        Picker("Category", selection: $editableCategory) {
                            ForEach(InventoryItem.predefinedCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.stoqlyPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.stoqlyCard)
                        .cornerRadius(AppTheme.radiusMd)
                    }

                    storagePickerSection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption).foregroundColor(.stoqlyDanger)
                }

                HStack(spacing: 12) {
                    Button("Try Again") { resetCapture() }
                        .font(.subheadline)
                        .foregroundColor(.stoqlyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.stoqlyPrimaryTint)
                        .cornerRadius(AppTheme.radiusMd)

                    Button(matchedExistingItem != nil ? "Update Count" : "Add to Inventory") {
                        Task { await saveSingleItem() }
                    }
                    .stoqlyButtonStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(editableName.trimmingCharacters(in: .whitespaces).isEmpty || !isStorageSelected)
                }
            }
            .padding()
        }
    }

    // ── Shelf scan (multiple products) ──────────────────────────────────────

    private var shelfScanReviewView: some View {
        VStack(spacing: 0) {
            if parsedItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No products detected")
                        .font(.title3).fontWeight(.semibold)
                    Text("Try a clearer photo or move closer to the shelf.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { resetCapture() }
                        .stoqlyButtonStyle()
                    Spacer()
                }
                .padding()
            } else {
                List {
                    Section {
                        storagePickerSection
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    Section {
                        ForEach($parsedItems) { $item in
                            EditableItemRow(item: $item, selectedStorage: selectedStorage)
                        }
                        .onDelete { parsedItems.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text("\(parsedItems.count) product\(parsedItems.count == 1 ? "" : "s") found")
                            Spacer()
                            Text("Swipe to remove")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                VStack(spacing: 12) {
                    Divider()
                    HStack(spacing: 12) {
                        Button("Re-take") { resetCapture() }
                            .font(.subheadline)
                            .foregroundColor(.stoqlyPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(AppTheme.radiusMd)

                        Button("Save All (\(parsedItems.count))") {
                            Task { await saveAllItems() }
                        }
                        .stoqlyButtonStyle()
                        .frame(maxWidth: .infinity)
                        .disabled(!isStorageSelected)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
            Text("Saving items…")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Shared sub-views

    private var storagePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage area")
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
            if !storages.isEmpty && selectedStorage == nil {
                Text("Select a storage to enable photo inventory.")
                    .font(.caption)
                    .foregroundColor(.stoqlyWarning)
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.stoqlyAccent)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            content()
                .padding(10)
                .background(Color.stoqlyCard)
                .cornerRadius(AppTheme.radiusMd)
        }
    }

    private func resetCapture() {
        capturedImage = nil
        parsedItem = nil
        parsedItems = []
        matchedExistingItem = nil
        step = .capture
    }

    // MARK: - Logic: Analyse

    private func analyseImage(_ image: UIImage) async {
        guard usageManager.canUse(.image, isPro: subscriptionManager.isPro) else {
            await MainActor.run { showingPaywall = true }
            return
        }

        await MainActor.run {
            capturedImage = image
            step = .analysing
            errorMessage = nil
        }

        let compressed = image.jpegData(compressionQuality: 0.7) ?? Data()

        do {
            let items = try await AIInventoryService.shared.identifyProduct(imageData: compressed)
            usageManager.recordUse(.image)

            let storage = selectedStorage

            await MainActor.run {
                // Populate multi-product list (shelf scan path)
                parsedItems = items.map { EditableItem(from: $0) }
                parsedItems.applyNameMatching(in: storage)

                // Also set single-product form fields for the 1-item path
                let parsed = items.first
                parsedItem = parsed
                editableName     = parsed?.name ?? ""
                // Pre-fill quantity from what AI counted — user can adjust before saving
                editableQty      = {
                    guard let qty = parsed?.quantity, qty > 0 else { return "" }
                    return qty == qty.rounded() ? String(Int(qty)) : String(qty)
                }()
                editableUnit     = parsed?.unitSymbol ?? "pcs"
                editableCategory = parsed?.category ?? "Uncategorised"

                // Only attempt fuzzy match when a single product was returned
                if items.count == 1, let name = parsed?.name, let storage {
                    matchedExistingItem = storage.items.first {
                        $0.name.lowercased().contains(name.lowercased()) ||
                        name.lowercased().contains($0.name.lowercased())
                    }
                    if let existing = matchedExistingItem {
                        editableName     = existing.name
                        editableUnit     = existing.uom?.symbol ?? editableUnit
                        editableCategory = existing.category
                    }
                }

                step = .review
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                AnalyticsManager.shared.track(.smartCountFailed(mode: "photo", reason: error.localizedDescription))
                step = .capture
            }
        }
    }

    // MARK: - Logic: Save (single product)

    private func saveSingleItem() async {
        let name = editableName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let storage = selectedStorage
        guard let storage else {
            errorMessage = "Please select a storage area."
            return
        }

        let qty = Double(editableQty) ?? 0
        let matchedUOM = uoms.first { $0.symbol.lowercased() == editableUnit.lowercased() }

        if let existing = matchedExistingItem {
            let count = InventoryCount(previousQuantity: existing.currentQuantity, countedQuantity: qty, notes: "Photo inventory")
            existing.countHistory.append(count)
            existing.currentQuantity = qty
            existing.updatedAt = Date()
            let event = ActivityEvent(
                eventType: "ItemCounted",
                itemName: existing.name,
                storageName: storage.name,
                notes: "Updated via photo inventory",
                performedBy: "You"
            )
            modelContext.insert(event)
        } else {
            let item = InventoryItem(
                name: name,
                currentQuantity: qty,
                category: editableCategory,
                storage: storage,
                uom: matchedUOM
            )
            modelContext.insert(item)
            let event = ActivityEvent(
                eventType: "ItemAdded",
                itemName: name,
                storageName: storage.name,
                notes: "Added via photo inventory",
                performedBy: "You"
            )
            modelContext.insert(event)
        }

        modelContext.safeSave(context: "ImageInventorySingleSave")
        AnalyticsManager.shared.track(.smartCountCompleted(mode: "photo", itemCount: 1))
        dismiss()
    }

    // MARK: - Logic: Save (shelf scan — multiple products)

    private func saveAllItems() async {
        guard let storage = selectedStorage else { return }
        step = .saving

        let itemsToSave = parsedItems.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }

        for editable in itemsToSave {
            let matchedUOM = uoms.first {
                $0.symbol.lowercased() == (editable.unitSymbol?.lowercased() ?? "")
            }

            switch editable.match {
            case .existing(let existing):
                let qty = editable.quantity ?? existing.currentQuantity
                let count = InventoryCount(
                    previousQuantity: existing.currentQuantity,
                    countedQuantity: qty,
                    notes: "Photo shelf scan"
                )
                existing.countHistory.append(count)
                existing.currentQuantity = qty
                existing.updatedAt = Date()
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: storage.name,
                    notes: "Photo shelf scan",
                    performedBy: "You"
                )
                modelContext.insert(event)
            case .new:
                let item = InventoryItem(
                    name: editable.name,
                    description: "",
                    currentQuantity: editable.quantity ?? 0,
                    category: editable.category ?? "Uncategorised",
                    storage: storage,
                    uom: matchedUOM
                )
                modelContext.insert(item)
                let event = ActivityEvent(
                    eventType: "ItemAdded",
                    itemName: item.name,
                    storageName: storage.name,
                    notes: "Added via photo shelf scan",
                    performedBy: "You"
                )
                modelContext.insert(event)
            }
        }

        modelContext.safeSave(context: "ImageInventoryShelfSave")

        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "photo",
            itemCount: itemsToSave.count
        ))

        Task {
            for item in storage.items {
                FirestoreManager.shared.syncItem(item)
            }
        }

        dismiss()
    }
}

// MARK: - CameraPickerView

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
