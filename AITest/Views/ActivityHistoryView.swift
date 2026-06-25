import SwiftUI
import SwiftData

struct ActivityHistoryView: View {
    let events: [ActivityEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Actions like adding, counting, and deleting items will appear here.")
                    )
                } else {
                    ForEach(events, id: \.id) { event in
                        ActivityEventRow(event: event)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Activity History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
