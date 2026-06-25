import SwiftUI

/// Bottom toast pill used to confirm one-off destructive actions (item / storage
/// deletion). The toast is purely informational — no undo affordance.
struct ToastView: View {
    let message: String
    let icon: String        // SF Symbol name, e.g. "trash.fill"
    let iconColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.subheadline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .accessibilityIdentifier("deletionToastLabel")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.label).opacity(0.88))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Toast modifier

struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let msg = message {
                ToastView(message: msg, icon: "trash.fill", iconColor: .red)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 32)
                    .zIndex(999)
                    .animation(.spring(duration: 0.35), value: message)
            }
        }
        .animation(.spring(duration: 0.35), value: message)
    }
}

extension View {
    /// Show a bottom toast for `duration` seconds then auto-dismiss.
    func toast(message: Binding<String?>, duration: Double = 2.0) -> some View {
        modifier(ToastModifier(message: message))
            .onChange(of: message.wrappedValue) { _, newVal in
                guard newVal != nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    await MainActor.run { message.wrappedValue = nil }
                }
            }
    }
}
