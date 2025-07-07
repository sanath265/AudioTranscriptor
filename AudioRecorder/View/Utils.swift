//
//  Utils.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 05/07/25.
//
import SwiftUI
import AVFoundation

struct AlertError: Identifiable {
    let id = UUID()
    let msg: String
}

struct WaveformPlaceholder: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<150, id: \.self) { _ in
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 2, height: CGFloat.random(in: 10...40))
            }
        }
    }
}

struct WaveformView: View {
    let levels: [Float]
    var body: some View {
        HStack(alignment: .bottom, spacing: 0.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .foregroundStyle(Color.red)
                    .frame(width: 1.5, height: CGFloat(level) * 500)
            }
        }
    }
}
