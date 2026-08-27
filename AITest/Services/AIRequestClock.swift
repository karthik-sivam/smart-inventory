import Foundation

/// One-shot timer for an AI model call. `init` fires `ai_request_started`.
/// Call exactly one of `succeeded` / `empty` / `failed` / `finish(error:)`.
@MainActor
struct AIRequestClock {
    let feature: String
    let mode: String?
    private let startedAt: CFAbsoluteTime

    init(feature: String, mode: String?, inputBytes: Int? = nil) {
        self.feature = feature
        self.mode = mode
        self.startedAt = CFAbsoluteTimeGetCurrent()
        let kb: Int?
        if let inputBytes {
            kb = max(1, Int((Double(inputBytes) / 1024.0).rounded(.up)))
        } else {
            kb = nil
        }
        AnalyticsManager.shared.track(
            .aiRequestStarted(feature: feature, mode: mode, inputSizeKB: kb)
        )
    }

    private var durationMs: Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000))
    }

    func succeeded(itemCount: Int, provider: String = "claude") {
        AnalyticsManager.shared.track(
            .aiRequestSucceeded(
                feature: feature,
                mode: mode,
                itemCount: itemCount,
                durationMs: durationMs,
                provider: provider
            )
        )
    }

    func empty(reason: String) {
        AnalyticsManager.shared.track(
            .aiRequestEmpty(
                feature: feature,
                mode: mode,
                durationMs: durationMs,
                reason: reason
            )
        )
    }

    func finish(itemCount: Int, emptyReason: String = "no_items_returned") {
        if itemCount == 0 {
            empty(reason: emptyReason)
        } else {
            succeeded(itemCount: itemCount)
        }
    }

    func finish(error: Error, stage: String) {
        if let ai = error as? AIInventoryError, case .noItemsFound = ai {
            empty(reason: "no_items_found")
            return
        }
        AnalyticsManager.shared.track(
            .aiRequestFailed(
                feature: feature,
                mode: mode,
                stage: stage,
                errorClass: Self.errorClass(for: error),
                reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                durationMs: durationMs
            )
        )
    }

    static func errorClass(for error: Error) -> String {
        if let ai = error as? AIInventoryError {
            switch ai {
            case .networkError: return "network"
            case .invalidResponse: return "parse_error"
            case .missingAPIKey: return "server_error"
            case .noItemsFound: return "parse_error"
            }
        }
        if error is URLError { return "network" }
        if error is DecodingError { return "parse_error" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "network" }
        if ns.code == 429 { return "rate_limited" }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("429") || desc.contains("rate limit") { return "rate_limited" }
        if desc.contains("network") || desc.contains("offline") || desc.contains("internet") {
            return "network"
        }
        if desc.contains(" 5") || desc.contains("500") || desc.contains("502") || desc.contains("503") {
            return "server_error"
        }
        return "unknown"
    }
}
