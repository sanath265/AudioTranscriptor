import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

/// ViewModel managing AVAudioEngine, session, and recording logic
final class RecordingViewModel: ObservableObject {
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

    @AppStorage("audioFormat") private var audioFormat: String = "caf"
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
    init() {
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
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { self.hasPermission = granted }
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
        guard hasPermission else { sessionError = "Microphone access denied"; return }
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
}

/// SwiftUI view for audio recording screen
struct AudioRecorderView: View {
    @StateObject private var vm = RecordingViewModel()
    @State private var showSettings = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var path: [Destination] = []

    enum Destination: Hashable {
        case recordings
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                ZStack {
                    if showToast {
                        VStack {
                            Text(toastMessage)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 50)
                        .transition(.opacity)
                        .animation(.easeInOut, value: showToast)
                    }
                    VStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .stroke(lineWidth: 4)
                                .foregroundStyle(Color.gray.opacity(0.3))
                                .frame(width: 175, height: 175)
                                .scaleEffect(vm.isRecording ? 1.1 : 1.0)
                                .animation(vm.isRecording ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                                           value: vm.isRecording)
                            Text(vm.formattedDuration)
                                .font(.title).bold()
                        }
                        
                        WaveformView(levels: vm.levelHistory)
                            .frame(height: 100)
                            .padding(.horizontal)
                    }
                    .padding()
                    
                    VStack {
                        Spacer()
                        Group {
                            if !vm.isRecording {
                                Button { vm.startRecording() } label: {
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 60))
                                }
                                .tint(.red)
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                HStack(spacing: 50) {
                                    Button {
                                        if vm.isPaused {
                                            vm.resumeRecording()
                                            toastMessage = "Recording Resumed"
                                        } else {
                                            vm.pauseRecording()
                                            toastMessage = "Recording Paused"
                                        }
                                        showToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            withAnimation { showToast = false }
                                        }
                                    } label: {
                                        Image(systemName: vm.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                            .font(.system(size: 50))
                                    }
                                    .tint(.primary)
                                    Button { vm.stopRecording() } label: {
                                        Image(systemName: "stop.circle.fill")
                                            .font(.system(size: 50))
                                    }
                                    .tint(.red)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.isRecording)
                        .alert(item: Binding(
                            get: { vm.sessionError.map { AlertError(msg: $0) } },
                            set: { _ in vm.sessionError = nil }
                        )) { alert in
                            Alert(title: Text("Error"), message: Text(alert.msg))
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("New Recording")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        path.append(.recordings)
                    } label: {
                        Image(systemName: "list.bullet")
                            .imageScale(.large)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .recordings:
                    RecordingsListView()
                }
            }
        }
    }
}

private struct AlertError: Identifiable {
    let id = UUID()
    let msg: String
}

struct AudioRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { AudioRecorderView() }
    }
}

private struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("audioFormat") private var audioFormat: String = "caf"
    @AppStorage("audioBitRate") private var audioBitRate: Int = 128000
    @AppStorage("audioSampleRate") private var audioSampleRate: Double = 48000

    private let formats = ["caf", "m4a"]
    private let bitRates = [64000, 96000, 128000, 192000, 256000]
    private let allSampleRates = [12000.0, 24000.0, 48000.0]
    private var sampleRatesForFormat: [Double] {
        audioFormat == "m4a" ? [48000.0] : allSampleRates
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Format")) {
                    Picker("Format", selection: $audioFormat) {
                        ForEach(formats, id: \.self) {
                            Text($0.uppercased()).tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("Bit Rate")) {
                    Picker("Bit Rate", selection: $audioBitRate) {
                        ForEach(bitRates, id: \.self) {
                            Text("\($0 / 1000) kbps").tag($0)
                        }
                    }
                }
                Section(header: Text("Sample Rate")) {
                    Picker("Sample Rate", selection: $audioSampleRate) {
                        ForEach(sampleRatesForFormat, id: \.self) {
                            Text("\(Int($0)) Hz").tag($0)
                        }
                    }
                }
            }
            .navigationTitle("Audio Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onChange(of: audioFormat) { newFormat, _ in
                if newFormat == "m4a" {
                    if !sampleRatesForFormat.contains(audioSampleRate) {
                        audioSampleRate = sampleRatesForFormat.first!
                    }
                }
            }
            .onAppear {
                if !sampleRatesForFormat.contains(audioSampleRate) {
                    audioSampleRate = sampleRatesForFormat.first!
                }
            }
        }
    }
}

private struct RecordingsListView: View {
    @State private var recordings: [URL] = []
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        List(recordings, id: \.self) { url in
            NavigationLink(destination: RecordingDetailView(audioURL: url)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        if let attr = try? url.resourceValues(forKeys: [.creationDateKey]),
                           let date = attr.creationDate {
                            Text(date, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.circle")
                        .imageScale(.large)
                }
            }
        }
        .navigationTitle("Recordings")
        .onAppear(perform: loadRecordings)
    }

    private func loadRecordings() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let urls = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            recordings = urls.filter { ["caf", "m4a"].contains($0.pathExtension) }
                              .sorted { (lhs, rhs) in
                                  let ld = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                                  let rd = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                                 return ld > rd
                              }
        }
    }
}

struct RecordingDetailView: View {
    let audioURL: URL
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text("Transcript placeholder...\n\nSegments every 30 seconds will appear here.")
                    .padding()
            }
            .layoutPriority(1)

            WaveformPlaceholder()
                .frame(height: 150)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Slider(value: $currentTime, in: 0...duration)
                    .padding(.horizontal)

                HStack(spacing: 40) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
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

    
