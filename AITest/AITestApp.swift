//
//  AITestApp.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/9/25.
//

import SwiftUI
import SwiftData
import Firebase
import GoogleSignIn

@main
struct AITestApp: App {
    
    init()
    {
        FirebaseApp.configure()
        
        // Configure Google Sign-In
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("GoogleService-Info.plist not found or CLIENT_ID missing")
            return
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Storage.self,
            InventoryItem.self,
            UOM.self,
            InventoryCount.self
        ])
        
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(CurrencyManager())
    }
} 
