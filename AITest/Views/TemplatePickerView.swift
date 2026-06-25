import SwiftUI
import SwiftData

struct TemplatePickerView: View {
    let templates: [ItemTemplate]
    let onSelect: (ItemTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(templates, id: \.id) { template in
                Button {
                    onSelect(template)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        HStack(spacing: 8) {
                            Text(template.category)
                            Text("·")
                            Text(template.uomName)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Choose Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
