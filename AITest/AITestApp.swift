//
//  AITestApp.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/9/25.
//

import SwiftUI
import SwiftData

@main
struct AITestApp: App {
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
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(CurrencyManager())
    }
} 