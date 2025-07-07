# Audio Transcriptor

A simple iOS app that lets you record audio, automatically splits it into 30-second segments, sends each segment to the Lemon Fox transcription API, and displays a per-segment transcript as you play back. Built with SwiftUI, SwiftData (CoreData under the hood), and modern Swift concurrency (async/await).

---

## Features

* **Record Audio**: Uses `AVAudioSession`/ `AVAudioApplication` for seamless microphone permission handling, background recording, and interruption recovery.
* **Automatic Segmentation**: Splits every recording into 30-second chunks using `AVAssetExportSession`.
* **Transcription**: Sends each segment to [LemonFox.ai](https://lemonfox.ai) via their `audio/transcriptions` endpoint, collects the returned text, and stores it alongside your recordings.
* **SwiftData Persistence**: Stores each `RecordingEntry` (original file URL, segment URLs, and segment transcripts) in a typed SwiftData model.
* **Playback & Live Transcript**: As you play back a recording, the UI highlights the current 30-second transcript chunk in a card-style view.
* **Progress & Status**: The recordings list shows a linear progress bar and a red/green status icon for "transcribed vs. pending" segments.

---

## Requirements

* **Xcode**: 15.4 or later
* **iOS Deployment Target**: 17.0+ recommended
* **Swift**: 5.9/ SwiftUI
* **SwiftData**: (requires Xcode 15+)
* **Network**: connectivity to call the LemonFox API

---

## Installation & Setup

### 1. Clone the Repository

```bash
git clone [https://github.com/your-username/AudioTranscriptor.git](https://github.com/your-username/AudioTranscriptor.git)
cd AudioTranscriptor
```

## 2. Configure your Lemon Fox API key

**Do NOT commit your real key to source control.**

### Recommended: Proxy through your own backend

Host a small server that holds the key and proxies requests. Point `LemonFoxAPIClient` at your proxy URL to remove secrets from the app entirely.

### If embedding in the app

1.  Create an ignored file `Secrets.xcconfig` next to the Xcode project:

    ```ini
    // Secrets.xcconfig
    LEMONFOX_API_KEY = your_real_api_key_here
    ```

2.  Add `Secrets.xcconfig` to your `.gitignore` file.

3.  In your Xcode scheme's **Run > Arguments > Environment Variables**, add:

    ```ini
    LEMONFOX_API_KEY = your_real_api_key_here
    ```

4.  In `LemonFoxAPIClient.swift`, load the key:

    ```swift
    let apiKey = ProcessInfo.processInfo.environment["LEMONFOX_API_KEY", default: ""]
    ```

## 3. Open in Xcode

```bash
open AudioTranscriptor.xcodeproj
```

Of course. Here is that section formatted for a `readme.md` file.

-----

## 4\. Run on Device or Simulator

  * **Simulator:** Recording will work, but you'll need to provide an audio file for transcription.
  * **Device:** Build & run, then grant microphone permission when prompted.

## How It Works

  * **RecordingViewModel:** Manages permissions, AV session, and recording. When recording stops, it calls `segmentAudio(url:)`.
  * **segmentAudio(url:)**: Uses an `AVAssetExportSession` to slice the file into segments and then calls a function to transcribe them.
  * **LemonFoxAPIClient:** Provides methods for transcription, handling `multipart/form-data` construction and authentication.
  * **SwiftData Model:**
    ```swift
    @Model
    class RecordingEntry {
        @Attribute(.unique) var id: UUID
        var originalURLString: String
        @Attribute(.transformable, default: []) var segmentURLStrings: [String]
        @Attribute(.transformable, default: []) var segmentTranscriptions: [String]
        var createdAt: Date
    }
    ```
  * **UI:**
      * **List View:** Shows each recording's date and a progress/status icon.
      * **Detail View:** Plays audio, tracks playback time, and displays the matching transcript.

## Project Structure
```
AudioTranscriptor/
├── AudioRecorder/
│   ├── APIRequest/
│   │   └── TranscriptionAPIClient.swift
│   ├── Model/
│   │   └── RecordingModel.swift
│   ├── View/
│   │   ├── Utils.swift
│   │   ├── RecordingDetailView.swift
│   │   ├── RecordingsListView.swift
│   │   ├── SettingsView.swift
│   │   └── AudioRecorderView.swift
│   └── ViewModel/
│       └── RecordingViewModel.swift
└── AudioTranscriptor/
    ├── Assets.xcassets
    ├── AudioTranscriptorApp.swift
    ├── ContentView.swift
    ├── Info.plist
    └── Item.swift
```

## Troubleshooting

  * **SwiftData Migration Errors:** If you change the SwiftData model, delete the app from the device or simulator to clear the old data store before rerunning.
  * **Permission Denied:** Attempting to record again after denying permission will prompt you to open Settings.
  * **Empty Transcript:** Check the console for logs to see if the API returned an unexpected response.
  * **API Errors:** Verify your API key and network connectivity.
