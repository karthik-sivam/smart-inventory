import SwiftUI
import SwiftData
import PhotosUI

struct SmartSalesPhotoView: View {
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @State private var step: PhotoStep = .capture
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var parsedRows: [ParsedSaleRow] = []
    @State private var errorMessage: String?

    enum PhotoStep { case capture, analyzing, review }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .capture: captureView
                case .analyzing: analyzingView
                case .review:
                    SaleEntryReviewView(
                        rows: $parsedRows,
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = .capture }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle(step == .review ? "Review Sales" : "Photo Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let img = newImage else { return }
            Task { await analyzeImage(img) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await analyzeImage(img)
                }
            }
        }
    }

    private var captureView: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundColor(.stoqlyAccent)
                    Text("Photograph a receipt, chit, or sales sheet with item names, quantities, and prices.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)

                Button { showingCamera = true } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.stoqlyAccent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.stoqlyDanger)
                }
            }
            .padding()
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            if let image = capturedImage {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(10)
            }
            ProgressView()
            Text("Reading your photo…").font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private func analyzeImage(_ image: UIImage) async {
        step = .analyzing
        capturedImage = image
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = String(localized: "ai.image.processFailed", defaultValue: "Could not process image.")
            step = .capture
            return
        }
        do {
            parsedRows = try await AIInventoryService.shared.parseSalesImage(
                imageData: data,
                knownItemNames: allItems.map(\.name)
            )
            AnalyticsManager.shared.track(.smartSalesModeSelected(mode: "photo"))
            step = .review
        } catch {
            errorMessage = error.localizedDescription
            step = .capture
        }
    }
}
