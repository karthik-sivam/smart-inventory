//
//  ContentView.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/9/25.
//

import SwiftUI
import SwiftData
import FirebaseAnalytics

struct ContentView: View {
    @AppStorage("stoqly_hasLoggedFirstOpen") private var hasLoggedFirstOpen = false
    @State private var currentAnnouncement: StoqlyAnnouncement?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var updateManager = AppUpdateManager.shared

    var body: some View {
        SplashScreenView()
            .onAppear {
                if !hasLoggedFirstOpen {
                    Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
                    hasLoggedFirstOpen = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stoqlyAnnouncement)) { notification in
                if let announcement = StoqlyAnnouncement(userInfo: notification.userInfo) {
                    currentAnnouncement = announcement
                }
            }
            .sheet(item: $currentAnnouncement) { announcement in
                AnnouncementPopupView(announcement: announcement) {
                    currentAnnouncement = nil
                }
                .sheetStyle()
            }
            .fullScreenCover(item: Binding(
                get: { updateManager.requirement },
                set: { _ in }   // read-only: the user cannot dismiss this
            )) { requirement in
                ForceUpdateView(requirement: requirement)
            }
            .task { await updateManager.check() }
            .onChange(of: scenePhase) { _, phase in
                // Re-check on foreground so a build can be retired mid-session
                // rather than only at cold launch.
                guard phase == .active else { return }
                Task { await updateManager.check() }
            }
    }
}

#Preview {
    ContentView()
}
