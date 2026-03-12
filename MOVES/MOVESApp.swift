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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
