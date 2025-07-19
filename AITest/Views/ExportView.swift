import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [InventoryItem]
    @Query private var storages: [Storage]
    
    @StateObject private var exportManager = ExportManager()
    @State private var selectedExportType: ExportManager.ExportType = .inventorySummary
    @State private var selectedFormat: ExportManager.ExportFormat = .csv
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Export Data")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Export Type Selection
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What to Export")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 12) {
                                ExportTypeCard(
                                    title: "Inventory Summary",
                                    subtitle: "Complete inventory with all items",
                                    icon: "list.bullet.clipboard",
                                    isSelected: selectedExportType == .inventorySummary
                                ) {
                                    selectedExportType = .inventorySummary
                                }
                                
                                ExportTypeCard(
                                    title: "Low Stock List",
                                    subtitle: "Items that need attention",
                                    icon: "exclamationmark.triangle",
                                    isSelected: selectedExportType == .lowStockList
                                ) {
                                    selectedExportType = .lowStockList
                                }
                                
                                ExportTypeCard(
                                    title: "Reorder List",
                                    subtitle: "Items ready for reordering",
                                    icon: "cart.badge.plus",
                                    isSelected: selectedExportType == .reorderList
                                ) {
                                    selectedExportType = .reorderList
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Format Selection
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Export Format")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 12) {
                                FormatCard(
                                    title: "Excel (CSV)",
                                    subtitle: "Open in Excel, Numbers, or Google Sheets",
                                    icon: "tablecells",
                                    isSelected: selectedFormat == .csv
                                ) {
                                    selectedFormat = .csv
                                }
                                
                                FormatCard(
                                    title: "PDF Report",
                                    subtitle: "Professional formatted report",
                                    icon: "doc.text",
                                    isSelected: selectedFormat == .pdf
                                ) {
                                    selectedFormat = .pdf
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Preview
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Preview")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ExportPreviewCard(
                                exportType: selectedExportType,
                                format: selectedFormat,
                                items: items,
                                storages: storages
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 20)
                }
                
                // Export Button
                VStack(spacing: 16) {
                    if exportManager.isExporting {
                        VStack(spacing: 8) {
                            ProgressView(value: exportManager.exportProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text("Exporting...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button(action: exportData) {
                        HStack {
                            if exportManager.isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            
                            Text(exportManager.isExporting ? "Exporting..." : "Export Data")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(exportManager.isExporting ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(exportManager.isExporting)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Complete", isPresented: $showingAlert) {
            Button("OK") {
                if exportedFileURL != nil {
                    showingShareSheet = true
                }
            }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func exportData() {
        let exportData = ExportManager.ExportData(
            items: items,
            storages: storages,
            exportType: selectedExportType,
            format: selectedFormat,
            timestamp: Date()
        )
        
        Task {
            if let fileURL = await exportManager.exportData(exportData) {
                await MainActor.run {
                    exportedFileURL = fileURL
                    alertMessage = "Your \(selectedFormat == .csv ? "Excel" : "PDF") file has been created successfully!"
                    showingAlert = true
                }
            } else {
                await MainActor.run {
                    alertMessage = "Failed to export data. Please try again."
                    showingAlert = true
                }
            }
        }
    }
}

struct ExportTypeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FormatCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 50, height: 50)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(12)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ExportPreviewCard: View {
    let exportType: ExportManager.ExportType
    let format: ExportManager.ExportFormat
    let items: [InventoryItem]
    let storages: [Storage]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: format == .csv ? "tablecells" : "doc.text")
                    .foregroundColor(.blue)
                
                Text(previewTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(format == .csv ? "CSV" : "PDF")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PreviewRow(label: "Items to export", value: "\(previewItemCount)")
                PreviewRow(label: "File size", value: "~\(estimatedFileSize)")
                PreviewRow(label: "Format", value: format == .csv ? "Excel compatible" : "Professional report")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var previewTitle: String {
        switch exportType {
        case .inventorySummary:
            return "Complete Inventory"
        case .lowStockList:
            return "Low Stock Items"
        case .reorderList:
            return "Reorder List"
        }
    }
    
    private var previewItemCount: Int {
        switch exportType {
        case .inventorySummary:
            return items.count
        case .lowStockList:
            return items.filter { $0.isLowStock || $0.isOutOfStock }.count
        case .reorderList:
            return items.filter { $0.isOutOfStock || $0.isLowStock }.count
        }
    }
    
    private var estimatedFileSize: String {
        let baseSize = previewItemCount * 100 // Rough estimate
        if baseSize < 1024 {
            return "\(baseSize) KB"
        } else {
            return "\(baseSize / 1024) MB"
        }
    }
}

struct PreviewRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView()
        .modelContainer(for: [Storage.self, InventoryItem.self, UOM.self, InventoryCount.self], inMemory: true)
} 