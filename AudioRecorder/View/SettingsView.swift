//
//  SettingsView.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 05/07/25.
//
import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("audioFormat") private var audioFormat: String = "m4a"
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

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView() }
    }
}
