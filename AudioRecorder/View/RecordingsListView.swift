//
//  RecordingsListView.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 05/07/25.
//
import SwiftUI
import AVFoundation
import SwiftData

struct RecordingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecordingEntry.createdAt, order: .reverse)
    private var entries: [RecordingEntry]

    var body: some View {
        List(entries, id: \.id) { entry in
            NavigationLink(destination: RecordingDetailView(audioURL: ((entry.originalURL ?? URL(string: ""))!),
                                                            transcripts: entry.segmentTranscriptions)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.originalURL?.lastPathComponent ?? "Unknown")
                            .font(.headline)
                        HStack {
                            Text(entry.createdAt, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            // Calculate percentage
                            let percent = Int((entry.segmentTranscriptions.count) / max(entry.segmentURLStrings.count, 1)) * 100
                            // Conditional icon and color
                            let isComplete = (percent == 100)
                            HStack(spacing: 4) {
                                Image(systemName: isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(isComplete ? .green : .red)
                                Text("\(percent)%")
                                    .font(.subheadline)
                                    .foregroundColor(isComplete ? .green : .red)
                            }
                        }
                        ProgressView(value: Double(entry.segmentTranscriptions.count),
                                     total: Double(max(entry.segmentURLStrings.count, 1)))
                            .progressViewStyle(.linear)
                    }
                    Spacer()
                    Image(systemName: "play.circle")
                        .imageScale(.large)
                }
                .onAppear { print(entry.segmentTranscriptions) }
            }
        }
        .navigationTitle("Recordings")
    }
}

struct RecordingsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RecordingsListView()
        }
        .modelContainer(for: RecordingEntry.self)
    }
}
