////
////  RecordingViewModel.swift
////  AudioTranscriptor
////
////  Created by sanath kavatooru on 02/07/25.
////
//
//import SwiftUI
//import Observation
//
//@Observable
//final class RecordingViewModel {
//    private let recorder: AudioRecorderServiceImpl
//    
//    init(recorder: AudioRecorderServiceImpl) { self.recorder = recorder }
//    
//    var state: AudioRecorderServiceImpl.State { recorder.state }
//    var level: Float { recorder.level }
//    
//    @MainActor
//    func recordTapped() async {
//        switch recorder.state {
//        case .idle:
//            try? await recorder.requestPermission()
//            try? await recorder.start()
//        case .recording: recorder.pause()
//        case .paused:    try? recorder.resume()
//        default: break
//        }
//    }
//    
//    func stopTapped() { recorder.stop() }
//}
