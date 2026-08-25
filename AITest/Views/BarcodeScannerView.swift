import SwiftUI
import VisionKit
import AVFoundation

// MARK: - BarcodeScannerView
//
// Uses DataScannerViewController (VisionKit, iOS 16+) — Apple's recommended
// high-level scanner. It owns the full camera + detection pipeline internally,
// avoiding the AVCaptureMetadataOutput XPC issues that plagued the raw
// AVFoundation approach.
//
// KEY: startScanning() MUST be called in viewDidAppear — calling it earlier
// (e.g. in makeUIViewController) silently no-ops and detection never starts.
// ScannerNavigationController handles this via its viewDidAppear override.
//
// PRESENTATION CONTRACT (read this before adding new call sites):
//
//   This view MUST be presented via `.fullScreenCover`, NOT `.sheet`. When a
//   view that hosts an AVFoundation capture session is presented as a sheet
//   inside another sheet, iOS routes the capture XPC to the wrong window
//   scene and the pipeline silently fails with:
//
//       FigXPCUtilities signalled err=-17281     (RemoteServiceNotFound)
//       FigCaptureSourceRemote: assert err == 0  (capture source bail)
//       (Fig) signalled err=-12710               (CMFigCapture session)
//
//   `.fullScreenCover` reparents the presented controller to the root scene
//   presentation chain, giving the capture pipeline a stable host. See the
//   working "Scan to Find" call site in ItemListView for the canonical
//   presentation pattern.
//
// SETUP REQUIRED in Xcode:
//   Target → Info → Custom iOS Target Properties → Add:
//     NSCameraUsageDescription  →  "Stoqly uses your camera to scan product barcodes."

// MARK: - ScannerNavigationController

@MainActor
private protocol ScannerNavigationLifecycleDelegate: AnyObject {
    func scannerDidAppear()
}

/// A UINavigationController subclass whose sole job is to call
/// `scanner.startScanning()` once the view hierarchy is fully on screen.
/// DataScannerViewController silently ignores startScanning() if called
/// before viewDidAppear, so this is the reliable hook.
private final class ScannerNavigationController: UINavigationController {
    weak var scanner: DataScannerViewController?
    weak var scannerLifecycleDelegate: ScannerNavigationLifecycleDelegate?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? scanner?.startScanning()
        scannerLifecycleDelegate?.scannerDidAppear()
    }
}

// MARK: - BarcodeScannerView

struct BarcodeScannerView: UIViewControllerRepresentable {

    let onScan: (String, String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorization == .denied || cameraAuthorization == .restricted {
            context.coordinator.cameraPermissionDenied(status: cameraAuthorization)
            return context.coordinator.makeFallbackViewController()
        }

        // Apple-Silicon simulators report isSupported == true (they inherit the
        // host's ANE) but the AVFoundation capture XPC has no real camera to
        // attach to, so DataScannerViewController emits a stream of -17281 /
        // -12710 errors and shows a black preview. Short-circuit to the
        // manual-entry fallback so the simulator UX is usable and the console
        // stays clean.
        #if targetEnvironment(simulator)
        return context.coordinator.makeFallbackViewController()
        #else
        // Device: require both VisionKit availability (camera permission +
        // OS support) and hardware support (ANE-capable device).
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
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner

        // ScannerNavigationController calls startScanning() in viewDidAppear.
        let nav = ScannerNavigationController(rootViewController: scanner)
        nav.scanner = scanner
        nav.scannerLifecycleDelegate = context.coordinator
        nav.navigationBar.tintColor = .white
        nav.navigationBar.barStyle = .black
        nav.navigationBar.isTranslucent = true

        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.cancelTapped)
        )
        scanner.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Manual",
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.manualTapped)
        )

        return nav
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate, ScannerNavigationLifecycleDelegate {

        let onScan: (String, String) -> Void
        let onCancel: () -> Void
        weak var scanner: DataScannerViewController?
        /// Used on simulator / unsupported devices where `scanner` is nil so
        /// the manual-entry alert still has a presenter.
        weak var fallbackPresenter: UIViewController?
        private var hasScanned = false
        private var hasTerminalOutcome = false
        private let startedAt = CFAbsoluteTimeGetCurrent()
        private var noCodeTimer: Timer?
        private static let noCodeTimeoutSeconds: TimeInterval = 30

        init(onScan: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        // MARK: DataScannerViewControllerDelegate

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasScanned,
                  case .barcode(let barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue,
                  !payload.isEmpty else { return }

            hasScanned = true
            finishWithoutResultEvent()
            let symbology = barcode.observation.symbology.rawValue

            // Stop scanning so it doesn't fire again while we dismiss.
            dataScanner.stopScanning()

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // onScan is called on the main thread; the caller's closure sets
            // formVM.barcode and dismisses the sheet.
            DispatchQueue.main.async { [weak self] in
                self?.onScan(payload, symbology)
                AdManager.shared.recordCompletion(event: .barcodeScanned)
            }
        }

        // MARK: Bar button actions

        @objc func cancelTapped() {
            scanner?.stopScanning()
            trackTerminalOutcome(
                outcome: "scanner_cancelled",
                provider: "none",
                symbology: nil,
                reason: "user_tapped_cancel"
            )
            onCancel()
        }

        @objc func manualTapped() {
            // Prefer the real scanner as presenter; fall back to the simulator
            // / unsupported-device VC so the alert always has somewhere to go.
            guard let presenter: UIViewController = scanner ?? fallbackPresenter else { return }
            let alert = UIAlertController(
                title: "Enter Barcode",
                message: "Type the barcode number manually.",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "e.g. 5012345678900"
                tf.keyboardType = .asciiCapable
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .allCharacters
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Use", style: .default) { [weak self] _ in
                guard let code = alert.textFields?.first?.text, !code.isEmpty else { return }
                self?.hasScanned = true
                self?.finishWithoutResultEvent()
                self?.scanner?.stopScanning()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self?.onScan(code, "Manual")
            })
            presenter.present(alert, animated: true)
        }

        // MARK: Fallback for Simulator / unsupported device

        func makeFallbackViewController() -> UIViewController {
            let vc = UIViewController()
            vc.view.backgroundColor = .black

            // Wrap in a UINavigationController so Cancel is reachable from
            // the nav bar — matches the live scanner's chrome.
            let nav = ScannerNavigationController(rootViewController: vc)
            nav.scannerLifecycleDelegate = self
            nav.navigationBar.tintColor = .white
            nav.navigationBar.barStyle = .black
            nav.navigationBar.isTranslucent = true

            vc.title = "Scan Barcode"
            vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Cancel", style: .plain,
                target: self, action: #selector(cancelTapped)
            )

            let label = UILabel()
            label.text = "Camera not available on this device.\nEnter the barcode manually instead."
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

            var config = UIButton.Configuration.filled()
            config.title = "Enter Manually"
            config.cornerStyle = .large
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            let btn = UIButton(configuration: config)
            btn.addTarget(self, action: #selector(manualTapped), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                btn.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24)
            ])

            // Remember the inner VC so `manualTapped` can present from it
            // even though `scanner` is nil on this code path.
            fallbackPresenter = vc
            return nav
        }

        // MARK: Analytics lifecycle

        func scannerDidAppear() {
            guard !hasScanned, !hasTerminalOutcome, noCodeTimer == nil else { return }
            noCodeTimer = Timer.scheduledTimer(
                timeInterval: Self.noCodeTimeoutSeconds,
                target: self,
                selector: #selector(noCodeTimeoutFired),
                userInfo: nil,
                repeats: false
            )
        }

        func cameraPermissionDenied(status: AVAuthorizationStatus) {
            trackTerminalOutcome(
                outcome: "camera_denied",
                provider: "none",
                symbology: nil,
                durationMs: 0,
                reason: "AVCaptureDevice authorizationStatus=\(status.rawValue)"
            )
        }

        @objc private func noCodeTimeoutFired() {
            guard !hasScanned, !hasTerminalOutcome else { return }
            scanner?.stopScanning()
            trackTerminalOutcome(
                outcome: "no_code_detected",
                provider: "none",
                symbology: nil,
                reason: "scanner_timeout_30s"
            )
            onCancel()
        }

        private func finishWithoutResultEvent() {
            guard !hasTerminalOutcome else { return }
            hasTerminalOutcome = true
            noCodeTimer?.invalidate()
            noCodeTimer = nil
        }

        private func trackTerminalOutcome(
            outcome: String,
            provider: String,
            symbology: String?,
            durationMs: Int? = nil,
            reason: String?
        ) {
            guard !hasTerminalOutcome else { return }
            hasTerminalOutcome = true
            noCodeTimer?.invalidate()
            noCodeTimer = nil
            let elapsedMs = durationMs ?? max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000))
            AnalyticsManager.shared.track(
                .barcodeScanResult(
                    outcome: outcome,
                    provider: provider,
                    symbology: symbology,
                    durationMs: elapsedMs,
                    reason: reason
                )
            )
        }
    }
}
