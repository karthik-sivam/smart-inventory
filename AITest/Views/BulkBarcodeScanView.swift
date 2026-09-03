import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

// MARK: - Bulk barcode scan (iOS-F2)
//
// Presented with `.fullScreenCover` only (same AVFoundation contract as
// BarcodeScannerView). Camera and review share one cover so SwiftUI does not
// drop the review sheet on dismiss.

struct BulkBarcodeScanFlowView: View {
    let storage: Storage
    var source: String = "storage_detail"
    var onComplete: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UOM.name) private var uoms: [UOM]
    @StateObject private var viewModel = BulkBarcodeScanViewModel()
    @StateObject private var scanHandler = BulkScanCodeHandler()
    @State private var step: Step = .scanning
    @State private var showingManualEntry = false
    @State private var manualCode = ""
    @State private var didEmitTerminal = false

    private enum Step {
        case scanning
        case review
    }

    var body: some View {
        Group {
            switch step {
            case .scanning:
                scanningLayer
            case .review:
                reviewLayer
            }
        }
        .onAppear {
            viewModel.bind(items: storage.items)
            scanHandler.onCode = { code, symbology in
                acceptCode(code, symbology: symbology)
            }
            if !didEmitTerminal {
                AnalyticsManager.shared.track(.barcodeBulkScanStarted(source: source))
            }
        }
        .alert(
            L("bulkScan.manualTitle", "Enter barcode"),
            isPresented: $showingManualEntry
        ) {
            TextField(L("bulkScan.manualPlaceholder", "e.g. 5012345678900"), text: $manualCode)
                .keyboardType(.asciiCapable)
            Button(L("Cancel", "Cancel"), role: .cancel) {
                manualCode = ""
            }
            Button(L("Use", "Use")) {
                let code = manualCode
                manualCode = ""
                acceptCode(code, symbology: "Manual")
            }
        } message: {
            Text(L("bulkScan.manualMessage", "Type the barcode number, then keep scanning."))
        }
    }

    // MARK: Camera

    private var scanningLayer: some View {
        ZStack(alignment: .bottom) {
            BulkBarcodeScannerRepresentable(handler: scanHandler)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(L("Cancel", "Cancel")) {
                        abandon(stage: viewModel.scannedCount == 0 ? "empty" : "camera")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Spacer()

                    Text(L("bulkScan.toolbar", "Bulk barcode scan"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    Button(L("bulkScan.manual", "Type code")) {
                        showingManualEntry = true
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Button(L("Done", "Done")) {
                        goToReview()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .disabled(viewModel.scannedCount == 0)
                    .opacity(viewModel.scannedCount == 0 ? 0.45 : 1)
                }
                .background(Color.black.opacity(0.45))

                Spacer()

                VStack(spacing: 6) {
                    Text(
                        String(
                            format: L("bulkScan.counter", "%d scanned"),
                            viewModel.scannedCount
                        )
                    )
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    if let last = viewModel.lastCode {
                        Text(last)
                            .font(.caption.monospaced())
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text(L("bulkScan.hint", "Point at the next barcode. Same code adds quantity."))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color.black)
    }

    // MARK: Review

    private var reviewLayer: some View {
        NavigationStack {
            List {
                ForEach(viewModel.rows) { row in
                    reviewRow(row)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.remove(id: row.id)
                            } label: {
                                Label(L("Delete", "Delete"), systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("bulkScan.reviewTitle", "Review scans"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("bulkScan.backToCamera", "Camera")) {
                        step = .scanning
                        viewModel.bind(items: storage.items)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save")) {
                        saveAll()
                    }
                    .disabled(viewModel.selectedRows.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
    }

    private func reviewRow(_ row: BulkBarcodeScanViewModel.QueuedRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.setSelected(id: row.id, selected: !row.isSelected)
            } label: {
                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(row.isSelected ? .stoqlyPrimary : .secondary)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(row.isSelected ? L("Selected", "Selected") : L("Not selected", "Not selected"))

            VStack(alignment: .leading, spacing: 6) {
                Text(row.badgeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(row.isExisting ? .stoqlyAccent : .stoqlyPrimary)

                if row.isExisting {
                    Text(row.existingName ?? row.name)
                        .font(.body.weight(.medium))
                } else {
                    TextField(L("Item name", "Item name"), text: Binding(
                        get: { row.name },
                        set: { viewModel.setName(id: row.id, name: $0) }
                    ))
                }

                Text(row.code)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    Button {
                        viewModel.setQuantity(id: row.id, quantity: row.quantity - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(row.quantity <= 1)

                    Text(row.quantity.smartFormatted)
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 36)

                    Button {
                        viewModel.setQuantity(id: row.id, quantity: row.quantity + 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .font(.title3)
                .foregroundColor(.stoqlyPrimary)
            }
        }
        .padding(.vertical, 4)
        .opacity(row.isSelected ? 1 : 0.45)
    }

    // MARK: Actions

    private func acceptCode(_ code: String, symbology: String) {
        let accepted = viewModel.ingest(code: code, symbology: symbology)
        guard accepted else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let normalized = BulkBarcodeScanViewModel.normalize(code)
        let row = viewModel.rows.first(where: { $0.code == normalized })
        if row?.isExisting != true {
            Task { await enrichNewCode(normalized) }
        }
    }

    private func enrichNewCode(_ code: String) async {
        let result = await BarcodeEnrichmentService.shared.enrichWithOutcome(barcode: code)
        guard let product = result.product else { return }
        await MainActor.run {
            viewModel.applyEnrichment(code: code, name: product.name, category: product.category)
        }
    }

    private func goToReview() {
        if viewModel.scannedCount == 0 {
            abandon(stage: "empty")
            return
        }
        viewModel.bind(items: storage.items)
        step = .review
    }

    private func abandon(stage: String) {
        guard !didEmitTerminal else {
            dismiss()
            return
        }
        didEmitTerminal = true
        AnalyticsManager.shared.track(
            .barcodeBulkScanAbandoned(
                stage: stage,
                scannedCount: viewModel.scannedCount,
                durationMs: viewModel.durationMs
            )
        )
        dismiss()
    }

    private func saveAll() {
        viewModel.errorMessage = nil
        let rows = viewModel.selectedRows
        guard !rows.isEmpty else { return }

        let defaultUOM = uoms.first(where: { $0.isDefault }) ?? uoms.first
        var runningCount = SubscriptionManager.shared.itemCount(in: storage, context: modelContext)
        var newCount = 0
        var updatedCount = 0
        var applied = 0

        for row in rows {
            if let existingId = row.existingItemId,
               let existing = storage.items.first(where: { $0.id == existingId }) {
                let previous = existing.currentQuantity
                let next = previous + row.quantity
                let count = InventoryCount(
                    previousQuantity: previous,
                    countedQuantity: next,
                    notes: "Bulk barcode scan",
                    countedBy: AuthManager.shared.actorName,
                    item: existing
                )
                existing.countHistory.append(count)
existing.lastCountedAt = count.countDate
                existing.currentQuantity = next
                existing.updatedAt = Date()
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: storage.name,
                    quantityBefore: previous,
                    quantityAfter: next,
                    notes: "Bulk barcode scan",
                    performedBy: AuthManager.shared.actorName
                )
                modelContext.insert(event)
                FirestoreManager.shared.syncActivity(event)
                FirestoreManager.shared.syncItem(existing)
                SpotlightManager.shared.index(existing)
                updatedCount += 1
                applied += 1
                continue
            }

            let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            guard SubscriptionManager.shared.canInsertNewItem(runningCount: &runningCount) else {
                continue
            }
            let item = InventoryItem(
                name: trimmedName,
                barcode: row.code,
                currentQuantity: row.quantity,
                category: row.category,
                storage: storage,
                uom: defaultUOM
            )
            modelContext.insert(item)
            AnalyticsManager.shared.track(.itemAdded(
                category: item.category,
                hasBarcode: true,
                hasPhoto: false,
                source: "barcode_bulk",
                inputMethod: "barcode"
            ))
            let event = ActivityEvent(
                eventType: "ItemAdded",
                itemName: item.name,
                storageName: storage.name,
                notes: "Added via bulk barcode scan",
                performedBy: AuthManager.shared.actorName
            )
            modelContext.insert(event)
            FirestoreManager.shared.syncActivity(event)
            FirestoreManager.shared.syncItem(item)
            SpotlightManager.shared.index(item)
            newCount += 1
            applied += 1
        }

        guard modelContext.safeSave(context: "BulkBarcodeScan") else {
            viewModel.errorMessage = L("bulkScan.saveFailed", "Couldn't save these scans. Please try again.")
            return
        }

        didEmitTerminal = true
        AnalyticsManager.shared.track(
            .barcodeBulkScanCompleted(
                scannedCount: rows.count,
                newCount: newCount,
                updatedCount: updatedCount,
                durationMs: viewModel.durationMs
            )
        )
        onComplete?(applied)
        dismiss()
    }
}

/// Stable callback so SwiftUI does not recreate the camera VC when the
/// overlay counter updates after each beep.
@MainActor
private final class BulkScanCodeHandler: ObservableObject {
    var onCode: (String, String) -> Void = { _, _ in }
}

// MARK: - VisionKit host (keep-open)

private struct BulkBarcodeScannerRepresentable: UIViewControllerRepresentable {
    let handler: BulkScanCodeHandler

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorization == .denied || cameraAuthorization == .restricted {
            return context.coordinator.makeFallbackViewController()
        }

        #if targetEnvironment(simulator)
        return context.coordinator.makeFallbackViewController()
        #else
        guard DataScannerViewController.isAvailable,
              DataScannerViewController.isSupported else {
            return context.coordinator.makeFallbackViewController()
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [
                    .ean8, .ean13, .upce,
                    .code39, .code93, .code128,
                    .itf14, .dataMatrix, .aztec,
                    .pdf417, .qr
                ])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner

        let host = BulkScannerHostController(scanner: scanner)
        return host
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.handler = handler
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var handler: BulkScanCodeHandler
        weak var scanner: DataScannerViewController?

        init(handler: BulkScanCodeHandler) {
            self.handler = handler
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      !payload.isEmpty else { continue }
                let symbology = barcode.observation.symbology.rawValue
                DispatchQueue.main.async { [weak self] in
                    self?.handler.onCode(payload, symbology)
                }
            }
        }

        func makeFallbackViewController() -> UIViewController {
            let vc = UIViewController()
            vc.view.backgroundColor = .black
            let label = UILabel()
            label.text = L(
                "bulkScan.cameraUnavailable",
                "Camera not available here.\nUse Type code to add barcodes to the list."
            )
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24)
            ])
            return vc
        }
    }
}

/// Starts VisionKit scanning in `viewDidAppear` (startScanning is a no-op earlier).
private final class BulkScannerHostController: UIViewController {
    let scanner: DataScannerViewController

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? scanner.startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}
