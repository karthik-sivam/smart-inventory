import SwiftData
import SwiftUI

// MARK: - Safe Save Helper
// Use modelContext.safeSave() everywhere instead of try? modelContext.save()
// On failure: logs to console and posts a notification for the error banner.

extension ModelContext {
    func safeSave(context: String = "") {
        do {
            try save()
        } catch {
            let msg = context.isEmpty ? error.localizedDescription
                : "[\(context)] \(error.localizedDescription)"
            print("SwiftData save failed: \(msg)")
            NotificationCenter.default.post(
                name: .swiftDataSaveError,
                object: msg
            )
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
