import SwiftUI
import SwiftData

struct StorageListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]
    
    @State private var searchText = ""
    @State private var showingAddStorage = false
    
    var filteredStorages: [Storage] {
        if searchText.isEmpty {
            return storages
        } else {
            return storages.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) || 
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Storages")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { showingAddStorage = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                SearchBar(text: $searchText, placeholder: "Search storages...")
                    .padding(.horizontal)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredStorages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text(searchText.isEmpty ? "No storages yet" : "No storages found")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                if searchText.isEmpty {
                                    Text("Create your first storage area")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(filteredStorages, id: \.id) { storage in
                                NavigationLink(destination: StorageDetailView(storage: storage)) {
                                    StorageCard(storage: storage)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddStorage) {
            AddStorageView()
        }
    }
}

struct StorageCard: View {
    let storage: Storage
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: storage.color) ?? .blue)
                .frame(width: 4, height: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(storage.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if !storage.location.isEmpty {
                    Text(storage.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !storage.storageDescription.isEmpty {
                    Text(storage.storageDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(storage.itemCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if storage.totalQuantity > 0 {
                    Text("\(String(format: "%.1f", storage.totalQuantity)) units")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct AddStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var location = ""
    @State private var description = ""
    @State private var selectedColor = "#007AFF"
    
    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#8E8E93", "#000000"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Storage Information")) {
                    TextField("Storage Name", text: $name)
                    TextField("Location (Optional)", text: $location)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Storage")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
        }
    }
    
    private func saveStorage() {
        let storage = Storage(
            name: name,
            location: location,
            description: description,
            color: selectedColor
        )
        
        modelContext.insert(storage)
        try? modelContext.save()
        
        // Track completion for ad system
        AdManager.shared.recordCompletion(event: .storageCreated)
        
        dismiss()
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// Extension to convert hex color to SwiftUI Color
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    StorageListView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 