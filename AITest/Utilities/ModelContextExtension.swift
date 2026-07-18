import SwiftData
import SwiftUI

// MARK: - Safe Save Helper
// Use modelContext.safeSave() everywhere instead of try? modelContext.save()
// On failure: logs to console and posts a notification for the error banner.

extension ModelContext {
    /// Saves the context. Returns `true` on success, `false` on failure.
    /// On failure: logs to console and posts `.swiftDataSaveError` for the error banner.
    @discardableResult
    func safeSave(context: String = "") -> Bool {
        do {
            try save()
            return true
        } catch {
            let msg = context.isEmpty ? error.localizedDescription
                : "[\(context)] \(error.localizedDescription)"
            print("SwiftData save failed: \(msg)")
            NotificationCenter.default.post(
                name: .swiftDataSaveError,
                object: msg
            )
            return false
        }
    }
}

extension Notification.Name {
    static let swiftDataSaveError = Notification.Name("swiftDataSaveError")
}

extension Double {
    /// Returns "5" for 5.0, "2.5" for 2.5, "0" for 0.0.
    var smartFormatted: String {
        if self == self.rounded(.towardZero) && !self.isInfinite && !self.isNaN {
            return String(format: "%.0f", self)
        }
        let s = String(format: "%.2f", self)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }
}
