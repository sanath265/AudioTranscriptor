//
//  RecordingModel.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 06/07/25.
//

import SwiftData
import Foundation

@Model
class RecordingEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var originalURLString: String
    var segmentURLStrings: [String]
    var segmentTranscriptions: [String]
    var createdAt: Date

    init(id: UUID = .init(),
         originalURL: URL,
         segmentURLStrings: [String] = [],
         segmentTranscriptions: [String] = [],
         createdAt: Date) {
        self.id = id
        self.originalURLString = originalURL.absoluteString
        self.segmentURLStrings = segmentURLStrings
        self.segmentTranscriptions = segmentTranscriptions
        self.createdAt = createdAt
    }

    var originalURL: URL? {
        URL(string: originalURLString)
    }
}
