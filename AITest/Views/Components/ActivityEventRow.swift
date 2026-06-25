import SwiftUI

struct ActivityEventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.displayIcon)
                .font(.system(size: 16))
                .foregroundColor(colorFromString(event.displayColor))
                .frame(width: 32, height: 32)
                .background(colorFromString(event.displayColor).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(event.itemName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(event.displayDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let actor = event.performedBy, !actor.isEmpty {
                    Text("by \(actor)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(event.occurredAt.relativeFormatted)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        default: return .gray
        }
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
