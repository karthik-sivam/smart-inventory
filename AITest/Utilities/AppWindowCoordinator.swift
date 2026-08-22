import SwiftUI
import SwiftData
import UIKit

/// Re-roots the key window when the app language changes so sheets, navigation
/// stacks, and @StateObject-cached strings are rebuilt in the new locale.
@MainActor
enum AppWindowCoordinator {
    private static weak var modelContainer: ModelContainer?
    private static weak var currencyManager: CurrencyManager?

    static func register(modelContainer: ModelContainer, currencyManager: CurrencyManager) {
        self.modelContainer = modelContainer
        self.currencyManager = currencyManager
        applySemanticDirection(to: keyWindow)
    }

    /// Forces UIKit RTL/LTR so in-app language switches (device stays LTR) still flip layout.
    static func applySemanticDirection(to window: UIWindow? = nil) {
        let isRTL = LocalizationManager.shared.layoutDirection == .rightToLeft
        let attribute: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attribute
        if let window {
            window.semanticContentAttribute = attribute
        }
    }

    static func reRootWindow(animated: Bool = true) {
        guard
            let window = keyWindow,
            let modelContainer,
            let currencyManager
        else { return }

        let localizationManager = LocalizationManager.shared
        let isRTL = localizationManager.layoutDirection == .rightToLeft
        let attribute: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        applySemanticDirection(to: window)

        let rootView = ContentView()
            .environmentObject(AuthManager.shared)
            .environmentObject(currencyManager)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(FirestoreManager.shared)
            .environmentObject(TrackingPermissionManager.shared)
            .environmentObject(NotificationManager.shared)
            .environmentObject(TeamManager.shared)
            .environmentObject(localizationManager)
            .environment(\.locale, localizationManager.effectiveLocale())
            .environment(\.layoutDirection, localizationManager.layoutDirection)
            .modelContainer(modelContainer)

        let hosting = UIHostingController(rootView: AnyView(rootView))
        hosting.view.backgroundColor = .systemBackground
        hosting.view.semanticContentAttribute = attribute
        window.semanticContentAttribute = attribute

        let applyRoot = {
            window.rootViewController = hosting
        }

        if animated {
            UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: applyRoot)
        } else {
            applyRoot()
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
