import SwiftUI

struct SheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, 16)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
    }
}

extension View {
    func sheetStyle() -> some View {
        modifier(SheetStyle())
    }
}

