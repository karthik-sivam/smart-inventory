import Foundation

/// Gating for the recurring Dashboard feedback invite (S42).
enum FeedbackPromptManager {
    static let intervalDays = 60
    static let minInstallDays = 7

    static let installDateKey = "installDate"
    static let lastShownKey = "feedbackPromptLastShown"

    static func recordInstallIfNeeded() {
        guard UserDefaults.standard.double(forKey: installDateKey) == 0 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: installDateKey)
    }

    static func shouldShow(itemCount: Int) -> Bool {
        recordInstallIfNeeded()
        guard itemCount >= 1 else { return false }
        let now = Date().timeIntervalSince1970
        let installedAt = UserDefaults.standard.double(forKey: installDateKey)
        guard now - installedAt >= Double(minInstallDays) * 86_400 else { return false }
        let lastShown = UserDefaults.standard.double(forKey: lastShownKey)
        if lastShown == 0 { return true }
        return now - lastShown >= Double(intervalDays) * 86_400
    }

    static func markShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastShownKey)
    }

    #if DEBUG
    static let previewNotification = Notification.Name("stoqly.previewFeedbackPrompt")

    static func debugForceEligible() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970 - Double(minInstallDays + 1) * 86_400,
            forKey: installDateKey
        )
        UserDefaults.standard.set(0.0, forKey: lastShownKey)
        NotificationCenter.default.post(name: previewNotification, object: nil)
    }
    #endif
}
