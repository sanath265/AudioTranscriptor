//
//  AudioTranscriptorApp.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 02/07/25.
//

import SwiftUI
import SwiftData

@main
struct AudioTranscriptorApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RecordingEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

//    let recorder = AudioRecorderServiceImpl()
    var body: some Scene {
        WindowGroup {
            NavigationView {
                AudioRecorderView(context: sharedModelContainer.mainContext)
            }
            .modelContainer(sharedModelContainer)
        }
    }
}
