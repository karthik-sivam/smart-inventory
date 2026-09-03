import Foundation
import SwiftUI

enum SmartCountConfig {
    nonisolated(unsafe) static var autoAcceptThreshold: Double = 0.85
}

enum SmartReviewResolution: Equatable {
    case pending
    case confirmed
    case dismissed
}

enum SmartReviewFixture {
    static var isSmartCountEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.contains("SmartCountReviewFixture") }
#else
        false
#endif
    }

    static var isSmartSalesEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.contains("SmartSalesReviewFixture") }
#else
        false
#endif
    }
}

struct SmartConfidenceChip: View {
    let confidence: Double

    private var color: Color {
        if confidence < 0.5 { return .red }
        if confidence < SmartCountConfig.autoAcceptThreshold { return .orange }
        return .green
    }

    private var percentage: Int {
        Int((min(max(confidence, 0), 1) * 100).rounded())
    }

    var body: some View {
        Text("\(percentage)%")
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Confidence \(percentage) percent")
    }
}

struct SmartAutoAcceptedRow: View {
    let name: String
    let quantity: Double
    let unitSymbol: String?
    let confidence: Double
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(
                    [quantity.smartFormatted, unitSymbol ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            SmartConfidenceChip(confidence: confidence)
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(name)")
        }
        .padding(.vertical, 4)
    }
}

struct SmartReviewActionBar: View {
    let resolution: SmartReviewResolution
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onConfirm) {
                Label("Confirm", systemImage: "checkmark")
            }
            .foregroundColor(resolution == .confirmed ? .green : .primary)

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(action: onDismiss) {
                Label(resolution == .dismissed ? "Undo" : "Dismiss", systemImage: "xmark")
            }
            .foregroundColor(resolution == .dismissed ? .secondary : .red)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.borderless)
    }
}
