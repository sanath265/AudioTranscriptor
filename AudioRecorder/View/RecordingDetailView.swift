//
//  RecordingDetailView.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 05/07/25.
//
import SwiftUI
import AVFoundation
import SwiftData

struct RecordingDetailView: View {
    let audioURL: URL
    let transcripts: [String]
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var timer: Timer?

    private let segmentDuration: TimeInterval = 30

    private var currentTranscriptIndex: Int {
        guard !transcripts.isEmpty else { return 0 }
        let idx = Int(currentTime / segmentDuration)
        return min(idx, transcripts.count - 1)
    }

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if transcripts.isEmpty {
                        Text("Transcript not available.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        // Segment indicator
                        Text("Segment \(currentTranscriptIndex + 1) of \(transcripts.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Transcript card
                        Text(transcripts[currentTranscriptIndex])
                            .font(.body)
                            .foregroundColor(.red)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
            .layoutPriority(1)
            // Optional: further refine with a clipShape or extra padding
            //.clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 16) {
                // Time indicators
                HStack {
                    Text(formatTime(currentTime))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption)
                .padding(.horizontal)

                // Seek slider
                Slider(
                    value: $currentTime,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        if !editing {
                            audioPlayer?.currentTime = currentTime
                        }
                    }
                )
                .padding(.horizontal)

                // Playback and skip controls
                HStack(spacing: 40) {
                    Button(action: {
                        // rewind 10 seconds
                        guard let player = audioPlayer else { return }
                        player.currentTime = max(player.currentTime - 10, 0)
                        currentTime = player.currentTime
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 30))
                    }
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                    }
                    Button(action: {
                        // forward 10 seconds
                        guard let player = audioPlayer else { return }
                        player.currentTime = min(player.currentTime + 10, duration)
                        currentTime = player.currentTime
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 30))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(audioURL.lastPathComponent)
        .onAppear(perform: preparePlayer)
        .onDisappear {
            audioPlayer?.stop()
            timer?.invalidate()
        }
    }

    private func preparePlayer() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            duration = audioPlayer?.duration ?? 1
            currentTime = 0
            audioPlayer?.prepareToPlay()
        } catch {
            print("Audio prep error: \(error)")
        }
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.pause()
            timer?.invalidate()
        } else {
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = audioPlayer {
                currentTime = player.currentTime
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


struct RecordingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { RecordingDetailView(audioURL: URL(fileURLWithPath: "/path/to/file"), transcripts: []) }
    }
}
