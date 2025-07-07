import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import SwiftData

struct AudioRecorderView: View {
    private let context: ModelContext
    @StateObject private var vm: RecordingViewModel
    @State private var showSettings = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var path: [Destination] = []

    init(context: ModelContext) {
        self.context = context
        _vm = StateObject(wrappedValue: RecordingViewModel(context: context))
    }

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

struct AudioRecorderView_Previews: PreviewProvider {
    static let schema = Schema([RecordingEntry.self])
    static let previewContainer = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )

    static var previews: some View {
        NavigationStack {
            AudioRecorderView(context: previewContainer.mainContext)
        }
        .modelContainer(previewContainer)
    }
}
    
