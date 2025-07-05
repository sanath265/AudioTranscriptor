//
//  Item.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 02/07/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
