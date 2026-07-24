import SwiftUI

struct StoqlyAnnouncement: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let url: URL?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              (userInfo["type"] as? String) == "announcement" else { return nil }
        let title = userInfo["title"] as? String ?? userInfo["gcm.notification.title"] as? String ?? ""
        let message = userInfo["message"] as? String ?? userInfo["gcm.notification.body"] as? String ?? ""
        guard !title.isEmpty || !message.isEmpty else { return nil }
        self.title = title
        self.message = message
        if let urlString = userInfo["url"] as? String, let parsed = URL(string: urlString) {
            self.url = parsed
        } else {
            self.url = nil
        }
    }
}

struct AnnouncementPopupView: View {
    let announcement: StoqlyAnnouncement
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Text(announcement.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ScrollView {
                Text(announcement.message)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            if let url = announcement.url {
                Button(String(localized: "announcement.learnMore", defaultValue: "Learn more")) {
                    openURL(url)
                }
                .font(.subheadline)
                .foregroundColor(.stoqlyPrimary)
            }

            Button(String(localized: "announcement.dismiss", defaultValue: "Dismiss")) {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.stoqlyPrimary)
            .accessibilityIdentifier("announcementDismiss")
        }
        .padding(24)
        .accessibilityIdentifier("announcementPopup")
        .presentationDetents([.medium, .large])
    }
}
