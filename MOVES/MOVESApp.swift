//
//  MOVESApp.swift
//  MOVES
//
//  Created by Suk Hee Kim on 3/10/26.
//

import SwiftUI
import SwiftData

@main
struct MOVESApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Move.self,
            UserProfile.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed (new fields added) — destroy and recreate the store.
            // This is safe during development; all move history is wiped on schema incompatibility.
            print("[MOVESApp] ⚠️ ModelContainer failed (\(error)). Destroying store and retrying...")
            do {
                let destroyConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
                try? FileManager.default.removeItem(at: destroyConfig.url)
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after store reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
