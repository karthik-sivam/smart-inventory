import SwiftUI
import SwiftData

struct EditStorageView: View {
    let storage: Storage
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String
    @State private var location: String
    @State private var description: String
    @State private var selectedColor: String
    @State private var supplierEmail: String
    
    private let colors = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE",
        "#5856D6", "#FF2D92", "#5AC8FA", "#FFCC02", "#FF6B35"
    ]
    
    init(storage: Storage) {
        self.storage = storage
        self._name = State(initialValue: storage.name)
        self._location = State(initialValue: storage.location)
        self._description = State(initialValue: storage.storageDescription)
        self._selectedColor = State(initialValue: storage.color)
        self._supplierEmail = State(initialValue: storage.supplierEmail)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Storage Information")) {
                    TextField("Storage Name", text: $name)
                    TextField("Location", text: $location)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Supplier") {
                    TextField("Supplier Email (optional)", text: $supplierEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section(header: Text("Storage Statistics")) {
                    HStack {
                        Text("Total Items")
                        Spacer()
                        Text("\(storage.itemCount)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Total Quantity")
                        Spacer()
                        Text(storage.totalQuantity.smartFormatted)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(storage.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Edit Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveStorage()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    private func saveStorage() {
        storage.name               = name
        storage.location           = location
        storage.storageDescription = description
        storage.color              = selectedColor
        storage.supplierEmail      = supplierEmail
        storage.updatedAt          = Date()

        modelContext.safeSave(context: "editStorage")

        // Sync to Firestore (fire-and-forget)
        FirestoreManager.shared.syncStorage(storage)

        AdManager.shared.recordCompletion(event: .storageUpdated)
        dismiss()
    }
}

#Preview {
    let storage = Storage(name: "Sample Storage", location: "Warehouse A", description: "Sample description")
    return EditStorageView(storage: storage)
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 