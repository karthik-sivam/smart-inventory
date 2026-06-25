import SwiftUI

// Attach .saveErrorBanner() to the root view (InventoryAppView).
// It listens for SwiftData save failures and shows a dismissible banner.

struct SaveErrorBanner: ViewModifier {
    @State private var message: String?
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible, let msg = message {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.white)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Spacer()
                            Button { isVisible = false } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isVisible)
            .onReceive(NotificationCenter.default.publisher(
                for: .swiftDataSaveError)) { notif in
                message = notif.object as? String ?? "Failed to save changes."
                isVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    isVisible = false
                }
            }
    }
}

extension View {
    func saveErrorBanner() -> some View {
        modifier(SaveErrorBanner())
    }
}
