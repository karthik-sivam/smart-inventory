import Foundation

/// Tracks sheet open/close for S37 generic sheet lifecycle analytics.
@MainActor
final class SheetAnalyticsTracker {
    private let sheet: String
    private let source: String?
    private var openedAt = Date()
    private(set) var didClose = false
    var didSave = false

    init(sheet: String, source: String? = nil) {
        self.sheet = sheet
        self.source = source
    }

    func trackOpened() {
        openedAt = Date()
        AnalyticsManager.shared.track(.sheetOpened(sheet: sheet, source: source))
    }

    func trackClosed(outcome: String) {
        guard !didClose else { return }
        didClose = true
        let seconds = Int(Date().timeIntervalSince(openedAt))
        AnalyticsManager.shared.track(.sheetClosed(sheet: sheet, outcome: outcome, seconds: seconds))
    }

    func trackDismissedIfNeeded() {
        guard !didSave else { return }
        trackClosed(outcome: "dismissed")
    }

    func trackCancelled() {
        guard !didSave else { return }
        trackClosed(outcome: "cancelled")
    }

    func trackSaved() {
        didSave = true
        trackClosed(outcome: "saved")
    }

    func trackSwitchedToPaywall() {
        trackClosed(outcome: "switched_to_paywall")
    }
}
