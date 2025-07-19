import Foundation
import SwiftUI
import SwiftData

class ExportManager: ObservableObject {
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    
    enum ExportType {
        case inventorySummary
        case lowStockList
        case reorderList
    }
    
    enum ExportFormat {
        case csv
        case pdf
    }
    
    struct ExportData {
        let items: [InventoryItem]
        let storages: [Storage]
        let exportType: ExportType
        let format: ExportFormat
        let timestamp: Date
    }
    
    func exportData(_ data: ExportData) async -> URL? {
        await MainActor.run {
            isExporting = true
            exportProgress = 0.0
        }
        
        let result: URL?
        
        switch data.format {
        case .csv:
            result = await exportToCSV(data)
        case .pdf:
            result = await exportToPDF(data)
        }
        
        await MainActor.run {
            isExporting = false
            exportProgress = 1.0
        }
        
        return result
    }
    
    private func exportToCSV(_ data: ExportData) async -> URL? {
        await MainActor.run { exportProgress = 0.2 }
        
        var csvContent = ""
        
        switch data.exportType {
        case .inventorySummary:
            csvContent = generateInventorySummaryCSV(data.items, storages: data.storages)
        case .lowStockList:
            csvContent = generateLowStockCSV(data.items)
        case .reorderList:
            csvContent = generateReorderCSV(data.items)
        }
        
        await MainActor.run { exportProgress = 0.6 }
        
        let fileName = generateFileName(data.exportType, format: "csv")
        return saveToFile(content: csvContent, fileName: fileName)
    }
    
    private func exportToPDF(_ data: ExportData) async -> URL? {
        await MainActor.run { exportProgress = 0.2 }
        
        let pdfContent = generatePDFContent(data)
        
        await MainActor.run { exportProgress = 0.6 }
        
        let fileName = generateFileName(data.exportType, format: "pdf")
        return saveToFile(content: pdfContent, fileName: fileName)
    }
    
    private func generateInventorySummaryCSV(_ items: [InventoryItem], storages: [Storage]) -> String {
        var csv = "Item Name,SKU,Storage,Current Quantity,UOM,Unit Cost,Total Value,Stock Status,Last Updated\n"
        
        for item in items {
            let row = [
                escapeCSVField(item.name),
                escapeCSVField(item.sku),
                escapeCSVField(item.storage?.name ?? "No Storage"),
                String(format: "%.2f", item.currentQuantity),
                escapeCSVField(item.uom?.symbol ?? ""),
                String(format: "%.2f", item.unitCost),
                String(format: "%.2f", item.totalValue),
                escapeCSVField(item.stockStatus),
                item.updatedAt.formatted(date: .abbreviated, time: .omitted)
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        // Add summary section
        csv += "\nSummary\n"
        csv += "Total Items,\(items.count)\n"
        csv += "Total Value,\(String(format: "%.2f", items.reduce(0) { $0 + $1.totalValue }))\n"
        csv += "Out of Stock,\(items.filter { $0.isOutOfStock }.count)\n"
        csv += "Low Stock,\(items.filter { $0.isLowStock }.count)\n"
        
        return csv
    }
    
    private func generateLowStockCSV(_ items: [InventoryItem]) -> String {
        let lowStockItems = items.filter { $0.isLowStock || $0.isOutOfStock }
        
        var csv = "Item Name,SKU,Storage,Current Quantity,Min Quantity,UOM,Stock Status,Action Required\n"
        
        for item in lowStockItems {
            let actionRequired = item.isOutOfStock ? "URGENT: Restock" : "Monitor/Reorder"
            let row = [
                escapeCSVField(item.name),
                escapeCSVField(item.sku),
                escapeCSVField(item.storage?.name ?? "No Storage"),
                String(format: "%.2f", item.currentQuantity),
                String(format: "%.2f", item.minQuantity),
                escapeCSVField(item.uom?.symbol ?? ""),
                escapeCSVField(item.stockStatus),
                escapeCSVField(actionRequired)
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        return csv
    }
    
    private func generateReorderCSV(_ items: [InventoryItem]) -> String {
        let reorderItems = items.filter { $0.isOutOfStock || $0.isLowStock }
        
        var csv = "Item Name,SKU,Storage,Current Quantity,Max Quantity,Reorder Quantity,UOM,Priority\n"
        
        for item in reorderItems {
            let reorderQuantity = max(item.maxQuantity - item.currentQuantity, item.minQuantity)
            let priority = item.isOutOfStock ? "HIGH" : "MEDIUM"
            
            let row = [
                escapeCSVField(item.name),
                escapeCSVField(item.sku),
                escapeCSVField(item.storage?.name ?? "No Storage"),
                String(format: "%.2f", item.currentQuantity),
                String(format: "%.2f", item.maxQuantity),
                String(format: "%.2f", reorderQuantity),
                escapeCSVField(item.uom?.symbol ?? ""),
                priority
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        return csv
    }
    
    private func generatePDFContent(_ data: ExportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        
        var pdfContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Inventory Report</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .header { text-align: center; margin-bottom: 30px; }
                .title { font-size: 24px; font-weight: bold; margin-bottom: 10px; }
                .subtitle { font-size: 16px; color: #666; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                th { background-color: #f2f2f2; font-weight: bold; }
                .summary { background-color: #f9f9f9; padding: 15px; margin: 20px 0; border-radius: 5px; }
                .urgent { color: #d32f2f; font-weight: bold; }
                .warning { color: #f57c00; font-weight: bold; }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="title">Smart Inventory Report</div>
                <div class="subtitle">Generated on \(dateFormatter.string(from: data.timestamp))</div>
            </div>
        """
        
        switch data.exportType {
        case .inventorySummary:
            pdfContent += generateInventorySummaryHTML(data.items, storages: data.storages)
        case .lowStockList:
            pdfContent += generateLowStockHTML(data.items)
        case .reorderList:
            pdfContent += generateReorderHTML(data.items)
        }
        
        pdfContent += """
        </body>
        </html>
        """
        
        return pdfContent
    }
    
    private func generateInventorySummaryHTML(_ items: [InventoryItem], storages: [Storage]) -> String {
        var html = """
        <h2>Inventory Summary</h2>
        <div class="summary">
            <strong>Total Items:</strong> \(items.count)<br>
            <strong>Total Value:</strong> $\(String(format: "%.2f", items.reduce(0) { $0 + $1.totalValue }))<br>
            <strong>Out of Stock:</strong> \(items.filter { $0.isOutOfStock }.count)<br>
            <strong>Low Stock:</strong> \(items.filter { $0.isLowStock }.count)
        </div>
        
        <table>
            <tr>
                <th>Item Name</th>
                <th>SKU</th>
                <th>Storage</th>
                <th>Quantity</th>
                <th>UOM</th>
                <th>Unit Cost</th>
                <th>Total Value</th>
                <th>Status</th>
            </tr>
        """
        
        for item in items {
            let statusClass = item.isOutOfStock ? "urgent" : (item.isLowStock ? "warning" : "")
            html += """
            <tr>
                <td>\(item.name)</td>
                <td>\(item.sku)</td>
                <td>\(item.storage?.name ?? "No Storage")</td>
                <td>\(String(format: "%.2f", item.currentQuantity))</td>
                <td>\(item.uom?.symbol ?? "")</td>
                <td>$\(String(format: "%.2f", item.unitCost))</td>
                <td>$\(String(format: "%.2f", item.totalValue))</td>
                <td class="\(statusClass)">\(item.stockStatus)</td>
            </tr>
            """
        }
        
        html += "</table>"
        return html
    }
    
    private func generateLowStockHTML(_ items: [InventoryItem]) -> String {
        let lowStockItems = items.filter { $0.isLowStock || $0.isOutOfStock }
        
        var html = """
        <h2>Low Stock & Out of Stock Items</h2>
        <div class="summary">
            <strong>Total Items Requiring Attention:</strong> \(lowStockItems.count)<br>
            <strong>Out of Stock:</strong> \(lowStockItems.filter { $0.isOutOfStock }.count)<br>
            <strong>Low Stock:</strong> \(lowStockItems.filter { $0.isLowStock }.count)
        </div>
        
        <table>
            <tr>
                <th>Item Name</th>
                <th>SKU</th>
                <th>Storage</th>
                <th>Current Qty</th>
                <th>Min Qty</th>
                <th>UOM</th>
                <th>Status</th>
                <th>Action</th>
            </tr>
        """
        
        for item in lowStockItems {
            let actionRequired = item.isOutOfStock ? "URGENT: Restock" : "Monitor/Reorder"
            let statusClass = item.isOutOfStock ? "urgent" : "warning"
            
            html += """
            <tr>
                <td>\(item.name)</td>
                <td>\(item.sku)</td>
                <td>\(item.storage?.name ?? "No Storage")</td>
                <td>\(String(format: "%.2f", item.currentQuantity))</td>
                <td>\(String(format: "%.2f", item.minQuantity))</td>
                <td>\(item.uom?.symbol ?? "")</td>
                <td class="\(statusClass)">\(item.stockStatus)</td>
                <td class="\(statusClass)">\(actionRequired)</td>
            </tr>
            """
        }
        
        html += "</table>"
        return html
    }
    
    private func generateReorderHTML(_ items: [InventoryItem]) -> String {
        let reorderItems = items.filter { $0.isOutOfStock || $0.isLowStock }
        
        var html = """
        <h2>Reorder List</h2>
        <div class="summary">
            <strong>Items Requiring Reorder:</strong> \(reorderItems.count)<br>
            <strong>High Priority:</strong> \(reorderItems.filter { $0.isOutOfStock }.count)<br>
            <strong>Medium Priority:</strong> \(reorderItems.filter { $0.isLowStock }.count)
        </div>
        
        <table>
            <tr>
                <th>Item Name</th>
                <th>SKU</th>
                <th>Storage</th>
                <th>Current Qty</th>
                <th>Max Qty</th>
                <th>Reorder Qty</th>
                <th>UOM</th>
                <th>Priority</th>
            </tr>
        """
        
        for item in reorderItems {
            let reorderQuantity = max(item.maxQuantity - item.currentQuantity, item.minQuantity)
            let priority = item.isOutOfStock ? "HIGH" : "MEDIUM"
            let priorityClass = item.isOutOfStock ? "urgent" : "warning"
            
            html += """
            <tr>
                <td>\(item.name)</td>
                <td>\(item.sku)</td>
                <td>\(item.storage?.name ?? "No Storage")</td>
                <td>\(String(format: "%.2f", item.currentQuantity))</td>
                <td>\(String(format: "%.2f", item.maxQuantity))</td>
                <td>\(String(format: "%.2f", reorderQuantity))</td>
                <td>\(item.uom?.symbol ?? "")</td>
                <td class="\(priorityClass)">\(priority)</td>
            </tr>
            """
        }
        
        html += "</table>"
        return html
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
    
    private func generateFileName(_ exportType: ExportType, format: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let timestamp = dateFormatter.string(from: Date())
        
        let typeName: String
        switch exportType {
        case .inventorySummary:
            typeName = "Inventory_Summary"
        case .lowStockList:
            typeName = "Low_Stock_List"
        case .reorderList:
            typeName = "Reorder_List"
        }
        
        return "SmartInventory_\(typeName)_\(timestamp).\(format)"
    }
    
    private func saveToFile(content: String, fileName: String) -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving file: \(error)")
            return nil
        }
    }
} 