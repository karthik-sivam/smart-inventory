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

    var body: some View {
        SplashScreenView()
            .onAppear {
                if !hasLoggedFirstOpen {
                    Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
                    hasLoggedFirstOpen = true
                }
            }
    }
}

#Preview {
    ContentView()
}
