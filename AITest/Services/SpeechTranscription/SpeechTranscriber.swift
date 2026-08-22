import Foundation
import Speech

// MARK: - SpeechTranscriber

/// Abstraction for turning spoken inventory into text (Apple on-device or Sarvam cloud).
protocol SpeechTranscriber {
    static func supports(locale: Locale) -> Bool
}

enum SpeechTranscriptionError: LocalizedError {
    case recognizerUnavailable
    case recordingFailed
    case networkError(String)
    case invalidResponse
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer unavailable."
        case .recordingFailed:
            return "Recording failed to start."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Could not read the speech recognition response."
        case .missingAPIKey:
            return "Cloud speech recognition is not configured."
        }
    }
}
