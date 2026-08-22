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
    }
}

#Preview {
    ContentView()
}
