////
////  AudioRecorderService.swift
////  AudioTranscriptor
////
////  Created by sanath kavatooru on 02/07/25.
////
//
//import AVFoundation
//import SwiftUI          // for @Observable
//
//@Observable
//@MainActor
//final class AudioRecorderServiceImpl: AudioRecorderService {
//    enum State { case idle, recording, paused, error(String) }
//    private(set) var state: State = .idle
//    private let engine = AVAudioEngine()
//    private var file: AVAudioFile?
//    
//    // published RMS for UI meter (0…1)
//    private(set) var level: Float = 0.0
//    
//    // MARK: – Public API
//    func requestPermission() async throws {
//        if try await AVAudioApplication.requestRecordPermission() == false {
//            throw RecorderError.permissionDenied
//        }
//    }
//    
//    func start(format: AVAudioFormat = .init(standardFormatWithSampleRate: 48_000, channels: 1)) async throws {
//        guard state == .idle else { return }
//        try configureSession()
//        
//        let url = Self.makeFileURL()
//        file = try AVAudioFile(forWriting: url, settings: format.settings)
//        
//        let input = engine.inputNode
//        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
//            guard let self, let f = self.file else { return }
//            do    { try f.write(from: buf) }
//            catch { self.state = .error(error.localizedDescription) }
//            self.computeLevel(from: buf)
//        }
//        try engine.start()
//        state = .recording
//    }
//    
//    func pause() {
//        guard state == .recording else { return }
//        engine.pause(); state = .paused
//    }
//    
//    func resume() throws {
//        guard state == .paused else { return }
//        try engine.start(); state = .recording
//    }
//    
//    func stop() {
//        engine.stop(); engine.inputNode.removeTap(onBus: 0)
//        file = nil; level = 0; state = .idle
//    }
//    
//    // MARK: – Private
//    private func configureSession() throws {
//        let ses = AVAudioSession.sharedInstance()
//        try ses.setCategory(.playAndRecord,
//                            mode: .default,
//                            options: [.defaultToSpeaker, .allowBluetooth])
//        try ses.setActive(true)
//        try ses.setPreferredSampleRate(48_000)
//        
//        observeNotifications()
//    }
//    
//    private func observeNotifications() {
//        NotificationCenter.default.addObserver(forName: .AVAudioSessionInterruption,
//                                               object: nil, queue: .main) { [weak self] n in
//            guard let self else { return }
//            if let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
//               type == 1 {          // began
//                self.pause()
//            } else {
//                try? AVAudioSession.sharedInstance().setActive(true)
//                try? self.resume()
//            }
//        }
//        NotificationCenter.default.addObserver(forName: .AVAudioSessionRouteChange,
//                                               object: nil, queue: .main) { _ in }
//    }
//    
//    private func computeLevel(from buf: AVAudioPCMBuffer) {
//        let rms = buf.floatChannelData!.pointee[0..<Int(buf.frameLength)]
//            .map { $0 * $0 }
//            .reduce(0, +) / Float(buf.frameLength)
//        level = min(max(sqrt(rms) * 10, 0), 1)
//    }
//    
//    static private func makeFileURL() -> URL {
//        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//        return dir.appendingPathComponent("\(UUID().uuidString).caf")
//    }
//    
//    enum RecorderError: Error { case permissionDenied }
//}
//
