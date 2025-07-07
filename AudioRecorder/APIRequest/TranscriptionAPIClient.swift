//
//  TranscriptionAPIClient.swift
//  AudioTranscriptor
//
//  Created by sanath kavatooru on 06/07/25.
//

import Foundation
import Network
import Speech

/// A simple API client for interacting with LemonFox audio transcription.
final class LemonFoxAPIClient {
    private let apiKey: String
    private let baseURL: URL
    private let maxRetryCount = 5
    private let baseDelay: TimeInterval = 1
    private var consecutiveFailures = 0
    private var offlineQueue: [URL] = []
    private let networkMonitor = NWPathMonitor()
    private var isNetworkReachable = true

    /// Initializes the client.
    /// - Parameters:
    ///   - apiKey: Your LemonFox API key.
    ///   - baseURL: The base URL for the LemonFox API.
    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.lemonfox.ai/v1/audio")!
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkReachable = (path.status == .satisfied)
            if self?.isNetworkReachable == true {
                Task { await self?.processOfflineQueue() }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    /// Transcribes a single audio file via the `/transcriptions` endpoint.
    /// - Parameter fileURL: Local file URL of the audio segment.
    /// - Returns: The transcription text (or empty string on failure).
    func transcribe(file fileURL: URL) async -> String? {
        if !isNetworkReachable {
            queueSegment(fileURL)
            return nil
        }

        for attempt in 0..<maxRetryCount {
            let endpoint = baseURL.appendingPathComponent("transcriptions")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            let boundary = UUID().uuidString
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            // Build the multipart body
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/\(fileURL.pathExtension)\r\n\r\n".data(using: .utf8)!)
            if let data = try? Data(contentsOf: fileURL) {
                body.append(data)
            }
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("english\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
            body.append("json\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            do {
                let (data, _) = try await URLSession.shared.upload(for: request, from: body)
                struct APIResponse: Decodable {
                    let text: String?
                    let transcription: String?
                }
                let res = try JSONDecoder().decode(APIResponse.self, from: data)
                let text = res.text ?? res.transcription ?? nil
                consecutiveFailures = 0
                return text
            } catch {
                let delay = baseDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        consecutiveFailures += 1
        if consecutiveFailures >= maxRetryCount {
            consecutiveFailures = 0
            return await fallbackLocalTranscribe(file: fileURL)
        }
        return nil
    }

    /// Transcribes multiple audio files in order.
    /// - Parameter files: Array of file URLs.
    /// - Returns: Transcriptions in same order.
    func transcribe(files: [URL]) async -> [String] {
        var output: [String] = []
        for file in files {
            let t = await transcribe(file: file)
            if let t {
                output.append(t)
            }
        }
        return output
    }
    private func queueSegment(_ fileURL: URL) {
        offlineQueue.append(fileURL)
    }

    private func processOfflineQueue() async {
        for url in offlineQueue {
            _ = await transcribe(file: url)
        }
        offlineQueue.removeAll()
    }

    private func fallbackLocalTranscribe(file fileURL: URL) async -> String? {
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer?.recognitionTask(with: request) { speechResult, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let speechResult = speechResult, speechResult.isFinal {
                        continuation.resume(returning: speechResult)
                    }
                }
            }
            return nil
        } catch {
            print("⚠️ Local transcription error:", error)
            return nil
        }
    }
}
