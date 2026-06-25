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

/// A UINavigationController subclass whose sole job is to call
/// `scanner.startScanning()` once the view hierarchy is fully on screen.
/// DataScannerViewController silently ignores startScanning() if called
/// before viewDidAppear, so this is the reliable hook.
private final class ScannerNavigationController: UINavigationController {
    weak var scanner: DataScannerViewController?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? scanner?.startScanning()
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

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {

        let onScan: (String, String) -> Void
        let onCancel: () -> Void
        weak var scanner: DataScannerViewController?
        /// Used on simulator / unsupported devices where `scanner` is nil so
        /// the manual-entry alert still has a presenter.
        weak var fallbackPresenter: UIViewController?
        private var hasScanned = false

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
            let symbology = barcode.observation.symbology.rawValue

            // Stop scanning so it doesn't fire again while we dismiss.
            dataScanner.stopScanning()

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // onScan is called on the main thread; the caller's closure sets
            // formVM.barcode and dismisses the sheet.
            DispatchQueue.main.async { [weak self] in
                self?.onScan(payload, symbology)
            }
        }

        // MARK: Bar button actions

        @objc func cancelTapped() {
            scanner?.stopScanning()
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
            let nav = UINavigationController(rootViewController: vc)
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
    }
}
