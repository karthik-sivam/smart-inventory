import AVFoundation
import Foundation

// MARK: - SarvamSpeechTranscriber

/// Records audio to a temp file and transcribes via Sarvam STT (Indian languages fallback).
@MainActor
final class SarvamSpeechTranscriber: ObservableObject {
    static func supports(locale: Locale) -> Bool {
        let lang = locale.language.languageCode?.identifier ?? ""
        return ["hi", "ta", "te", "kn", "ml"].contains(lang)
    }

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func startRecording() throws {
        stopRecording(deleteFile: true)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoqly_voice_\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        guard rec.record() else { throw SpeechTranscriptionError.recordingFailed }
        recorder = rec
    }

    func stopRecording(deleteFile: Bool = false) {
        recorder?.stop()
        recorder = nil
        if deleteFile, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func transcribe(languageCode: String) async throws -> String {
        guard let apiKey = SecretsManager.sarvamAPIKey, !apiKey.isEmpty else {
            throw SpeechTranscriptionError.missingAPIKey
        }
        guard let url = recordingURL else {
            throw SpeechTranscriptionError.recordingFailed
        }

        // Finalize the .m4a BEFORE reading it. An MPEG-4/m4a file only becomes a
        // valid, decodable file after stop() writes the trailing `moov` atom;
        // reading it mid-recording sends Sarvam a header-less file and yields
        // "Failed to read the file, please check the audio format."
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // Clean up the temp file when done (already stopped above — don't stop again).
        defer {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let fileData = try Data(contentsOf: url)
        guard !fileData.isEmpty else { throw SpeechTranscriptionError.recordingFailed }

        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        append("Content-Type: audio/x-m4a\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("saaras:v3\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n")
        append("\(languageCode)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        append("codemix\r\n")
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://api.sarvam.ai/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechTranscriptionError.networkError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SpeechTranscriptionError.networkError(msg)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transcript = json["transcript"] as? String,
            !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SpeechTranscriptionError.invalidResponse
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
