import SwiftUI
import AVFoundation

// MARK: - BarcodeScannerView
//
// Real AVFoundation camera-based barcode and QR code scanner.
//
// SETUP REQUIRED in Xcode:
//   Target → Info → Custom iOS Target Properties → Add:
//     Key:   NSCameraUsageDescription
//     Value: "Smart Inventory uses your camera to scan product barcodes
//             for quick inventory entry."
//
// Supported formats: EAN-8, EAN-13, UPC-A, UPC-E, QR Code, Code 128, Code 39, Code 93,
//                    ITF-14, DataMatrix, Aztec, PDF417

struct BarcodeScannerView: View {

    /// Called when a barcode is successfully scanned.
    let onScan: (String, String) -> Void   // (barcode value, format)
    let onCancel: () -> Void

    @StateObject private var coordinator = ScannerCoordinator()
    @State private var showManualEntry = false
    @State private var manualBarcode = ""
    @State private var lastScannedValue = ""
    @State private var flashOn = false

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreviewLayer(coordinator: coordinator)
                .ignoresSafeArea()

            // Scanning overlay
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Scan Barcode")
                        .font(.headline)
                        .foregroundColor(.white)
                        .shadow(radius: 2)

                    Spacer()

                    Button {
                        flashOn.toggle()
                        coordinator.toggleFlash(on: flashOn)
                    } label: {
                        Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title2)
                            .foregroundColor(flashOn ? .yellow : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()

                // Scan window
                ZStack {
                    // Dark overlay with hole
                    ScanWindowMask()

                    // Scan frame
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 260, height: 160)

                    // Corner accents
                    ScanCorners()

                    // Animated scan line
                    if coordinator.isScanning {
                        ScanLine()
                    }

                    // Success flash
                    if coordinator.didScan {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 260, height: 160)
                    }
                }

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    if let scanned = coordinator.lastScanned {
                        HStack {
                            Image(systemName: "barcode")
                            Text(scanned)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.85))
                        .cornerRadius(12)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Enter barcode manually", systemImage: "keyboard")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(12)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            coordinator.startScanning { value, format in
                guard value != lastScannedValue else { return }
                lastScannedValue = value
                // Haptic feedback
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Brief delay so user sees the success state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onScan(value, format)
                }
            }
        }
        .onDisappear { coordinator.stopScanning() }
        .alert("Permission Required", isPresented: $coordinator.showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { onCancel() }
        } message: {
            Text("Smart Inventory needs camera access to scan barcodes. Please enable it in Settings.")
        }
        .sheet(isPresented: $showManualEntry) {
            ManualBarcodeEntryView(barcode: $manualBarcode) { entered in
                onScan(entered, "Manual")
            }
        }
    }
}

// MARK: - Scanner Coordinator

@MainActor
final class ScannerCoordinator: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    @Published var isScanning = false
    @Published var didScan = false
    @Published var lastScanned: String?
    @Published var showPermissionAlert = false

    private var captureSession: AVCaptureSession?
    private var onScan: ((String, String) -> Void)?

    var previewLayer: AVCaptureVideoPreviewLayer?

    func startScanning(onScan: @escaping (String, String) -> Void) {
        self.onScan = onScan

        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                await setupSession()
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { await setupSession() }
                else { showPermissionAlert = true }
            default:
                showPermissionAlert = true
            }
        }
    }

    func stopScanning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
        isScanning = false
    }

    func toggleFlash(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func setupSession() async {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [
            .ean8, .ean13, .upce, .qr,
            .code128, .code39, .code93,
            .itf14, .dataMatrix, .aztec, .pdf417
        ]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        captureSession = session
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }

        let format = obj.type.rawValue

        Task { @MainActor in
            lastScanned = value
            didScan = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.didScan = false
            }

            onScan?(value, format)
        }
    }
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let coordinator: ScannerCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = coordinator.previewLayer else { return }
        previewLayer.frame = uiView.bounds
        if previewLayer.superlayer == nil {
            uiView.layer.addSublayer(previewLayer)
        }
    }
}

// MARK: - Visual Elements

struct ScanWindowMask: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .mask(
                ZStack {
                    Rectangle()
                    RoundedRectangle(cornerRadius: 16)
                        .frame(width: 260, height: 160)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
            .ignoresSafeArea()
    }
}

struct ScanCorners: View {
    let size: CGFloat = 28
    let thickness: CGFloat = 4
    let radius: CGFloat = 12

    var body: some View {
        ZStack {
            // Top-left
            cornerShape.rotationEffect(.degrees(0))   .offset(x: -115, y: -65)
            // Top-right
            cornerShape.rotationEffect(.degrees(90))  .offset(x:  115, y: -65)
            // Bottom-right
            cornerShape.rotationEffect(.degrees(180)) .offset(x:  115, y:  65)
            // Bottom-left
            cornerShape.rotationEffect(.degrees(270)) .offset(x: -115, y:  65)
        }
    }

    var cornerShape: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0),
                              control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size, y: 0))
        }
        .stroke(Color.green, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

struct ScanLine: View {
    @State private var offset: CGFloat = -72

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.green.opacity(0), .green, .green.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 240, height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    offset = 72
                }
            }
    }
}

// MARK: - Manual Barcode Entry

struct ManualBarcodeEntryView: View {
    @Binding var barcode: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Enter barcode or SKU", text: $barcode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                } header: {
                    Text("Manual Entry")
                } footer: {
                    Text("Enter a barcode number, EAN, UPC, or your own SKU code.")
                }
            }
            .navigationTitle("Manual Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use") {
                        guard !barcode.isEmpty else { return }
                        onConfirm(barcode)
                        dismiss()
                    }
                    .disabled(barcode.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BarcodeScannerView(
        onScan: { value, format in print("Scanned: \(value) (\(format))") },
        onCancel: {}
    )
}
