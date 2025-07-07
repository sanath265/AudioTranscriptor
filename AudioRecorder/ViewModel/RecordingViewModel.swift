

import Foundation
import SwiftData
import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

// Allow capturing AVAssetExportSession in Sendable closures
extension AVAssetExportSession: @unchecked Sendable {}

final class RecordingViewModel: ObservableObject {
    private let context: ModelContext
    // MARK: - Published State
    @Published var hasPermission = false
    @Published var sessionError: String?
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var duration: TimeInterval = 0
    @Published var currentLevel: Float = 0
    @Published var levelHistory: [Float] = []
    private let maxLevelCount = 200


    private var pausedByInterruption = false

    private var engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var startTime: Date?


    @AppStorage("audioFormat") private var audioFormat: String = "m4a"
    @AppStorage("audioBitRate") private var audioBitRate: Int = 128000
    @AppStorage("audioSampleRate") private var audioSampleRate: Double = 48000

    private var audioFileSettings: [String: Any] {
        switch audioFormat {
        case "m4a":
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVEncoderBitRateKey: audioBitRate,
                AVNumberOfChannelsKey: 1
            ]
        case "caf":
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVNumberOfChannelsKey: 1
            ]
        default:
            // fallback to AAC
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVEncoderBitRateKey: audioBitRate,
                AVNumberOfChannelsKey: 1
            ]
        }
    }
    
    private var recordFormat: AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: audioSampleRate, channels: 1)!
    }

    // MARK: - Computed
    var formattedDuration: String {
        guard isRecording else { return "00:00.000" }
        let elapsed = duration
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let milliseconds = Int((elapsed - floor(elapsed)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    // MARK: - Init
    init(context: ModelContext) {
        self.context = context
        requestPermission()
        observeNotifications()
        configureSession()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    // MARK: - Permission + Session
    func requestPermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { self.hasPermission = granted }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { self.hasPermission = granted }
            }
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            sessionError = error.localizedDescription
        }
    }

    private func installRecordingTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0,
                         bufferSize: 1024,
                         format: recordFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            do { try self.audioFile?.write(from: buffer) } catch {
                DispatchQueue.main.async { self.sessionError = error.localizedDescription }
            }
            self.updateLevel(buffer: buffer)
        }
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleInterruption),
                       name: AVAudioSession.interruptionNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleRouteChange),
                       name: AVAudioSession.routeChangeNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleBackground),
                       name: UIApplication.didEnterBackgroundNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleDidBecomeActive),
                       name: UIApplication.didBecomeActiveNotification,
                       object: nil)
        // Removed willResignActiveNotification observer to allow uninterrupted recording in background
    }

    // MARK: - Notifications
    @objc private func handleInterruption(_ note: Notification) {
        guard let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal)
        else { return }
        switch type {
        case .began:
            // pause for any interruption (call, other audio, lock)
            if isRecording && !isPaused {
                pausedByInterruption = true
                pauseRecording()
            }
        case .ended:
            // resume only if system indicates and we paused for interruption
            if let opts = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: opts).contains(.shouldResume),
               pausedByInterruption {
                pausedByInterruption = false
                resumeRecording()
            }
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        // Only handle old device unavailable (e.g., headphones unplugged) or new device available
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            DispatchQueue.main.async {
                if self.isRecording && !self.isPaused {
                    // Restart engine tap to adapt to new route
                    self.engine.pause()
                    self.installRecordingTap()
                    do {
                        try self.engine.start()
                    } catch {
                        self.sessionError = error.localizedDescription
                    }
                }
            }
        default:
            break
        }
    }

    @objc private func handleBackground() {
        // AVAudioEngine will continue if background mode enabled
    }

    @objc private func handleDidBecomeActive(_ note: Notification) {
        // Auto-resume after interruption if needed
        if isRecording && isPaused && pausedByInterruption {
            pausedByInterruption = false
            resumeRecording()
        }
    }





    // MARK: - Recording Controls
    func startRecording() {
        guard hasPermission else {
            DispatchQueue.main.async {
                self.sessionError = "Microphone access denied. Please enable Microphone access in Settings."
            }
            // Optionally prompt opening Settings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        configureSession()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = "rec_\(Date().timeIntervalSince1970).\(self.audioFormat)"
            let fileURL = docs.appendingPathComponent(filename)
            do {
                self.audioFile = try AVAudioFile(forWriting: fileURL, settings: self.audioFileSettings)
            } catch {
                DispatchQueue.main.async { self.sessionError = error.localizedDescription }
                return
            }

            self.engine.reset()
            self.installRecordingTap()
            do {
                try self.engine.start()
            } catch {
                DispatchQueue.main.async { self.sessionError = error.localizedDescription }
                return
            }

            DispatchQueue.main.async {
                self.startTime = Date()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    if let start = self.startTime {
                        self.duration = Date().timeIntervalSince(start)
                        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.duration
                    }
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.isRecording = true
                    self.isPaused = false  // show pause button initially
                }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.duration
            }
        }
    }

    func pauseRecording() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.pause()
        timer?.invalidate()
        DispatchQueue.main.async {
            withAnimation(.easeInOut) { self.isPaused = true }
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        }
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        installRecordingTap()
        do {
            try engine.start()
        } catch {
            DispatchQueue.main.async { self.sessionError = error.localizedDescription }
            return
        }
        DispatchQueue.main.async {
            self.startTime = Date().addingTimeInterval(-self.duration)
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                if let start = self.startTime {
                    self.duration = Date().timeIntervalSince(start)
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.duration
                }
            }
            withAnimation(.easeInOut) { self.isPaused = false }
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        timer?.invalidate()
        if let url = audioFile?.url {
            Task {
                await segmentAudio(fileURL: url, context: context)
            }
        }
        DispatchQueue.main.async {
            self.audioFile = nil
            self.levelHistory.removeAll()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.isRecording = false
                self.isPaused = false
                self.duration = 0
            }
        }
    }

    // MARK: - Level Meter
    private func updateLevel(buffer: AVAudioPCMBuffer) {
        let ch0 = buffer.floatChannelData![0]
        let frameCount = Int(buffer.frameLength)
        let bufferPointer = UnsafeBufferPointer(start: ch0, count: frameCount)
        var sumSquares: Float = 0
        for sample in bufferPointer {
            sumSquares += sample * sample
        }
        let meanSquare = sumSquares / Float(frameCount)
        let rms = sqrt(meanSquare)
        DispatchQueue.main.async {
            self.currentLevel = rms
            self.levelHistory.append(rms)
            if self.levelHistory.count > self.maxLevelCount {
                self.levelHistory.removeFirst()
            }
        }
    }
    /// Transcribes audio segments via LemonFox API.
    private func transcribeSegments(_ segmentPaths: [String]) async -> [String] {
        let client = LemonFoxAPIClient(apiKey: "YOUR_REAL_KEY")
        let urls = segmentPaths.compactMap { URL(string: $0) }
        return await client.transcribe(files: urls)
    }
    private func segmentAudio(
        fileURL: URL,
        segmentDuration: TimeInterval = 30,
        context: ModelContext
    ) async {
        let asset = AVURLAsset(url: fileURL)
        // Load total duration asynchronously
        let totalDuration: Double
        do {
            if #available(iOS 16.0, *) {
                let durationCM = try await asset.load(.duration)
                totalDuration = durationCM.seconds
            } else {
                totalDuration = asset.duration.seconds
            }
        } catch {
            print("Error loading asset duration: \(error)")
            return
        }
        var segmentPaths: [String] = []
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        var start: TimeInterval = 0

        while start < totalDuration {
            let end = min(start + segmentDuration, totalDuration)
            let timeRange = CMTimeRange(start: .init(seconds: start, preferredTimescale: 600),
                                        end: .init(seconds: end, preferredTimescale: 600))
            
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                print("Failed to create exporter")
                return
            }
            
            let outputURL = docs.appendingPathComponent("seg_\(Int(start))_\(fileURL.lastPathComponent)")
            exporter.outputURL = outputURL
            if audioFormat.lowercased() == "m4a" {
                exporter.outputFileType = .m4a
            } else {
                exporter.outputFileType = .caf
            }
            exporter.timeRange = timeRange

            let status = await withCheckedContinuation { (continuation: CheckedContinuation<AVAssetExportSession.Status, Never>) in
                exporter.exportAsynchronously {
                    continuation.resume(returning: exporter.status)
                }
            }
            if status == .completed {
                segmentPaths.append(outputURL.absoluteString)
            } else {
                print("Segment export failed: \(exporter.error?.localizedDescription ?? "Unknown error")")
            }
            
            print("💾 Exporting segment to:", outputURL.path)

            // After export completes, double-check:
            if FileManager.default.fileExists(atPath: outputURL.path) {
                print("✅ File exists at", outputURL.path)
            } else {
                print("❌ File missing at", outputURL.path)
            }
            
            start += segmentDuration
        }

        // Transcribe segments
        let transcriptions = await transcribeSegments(segmentPaths)
        print("transcriptions: \(transcriptions)")

        // Save RecordingEntry into SwiftData
        let entry = RecordingEntry(
            originalURL: fileURL,
            segmentURLStrings: segmentPaths,
            segmentTranscriptions: transcriptions,
            createdAt: Date.now
        )
        context.insert(entry)
        
        debugPrint(context)

        do {
            try context.save()
            print("Recording saved successfully.")
        } catch {
            print("Failed to save context: \(error)")
        }
    }

}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}
