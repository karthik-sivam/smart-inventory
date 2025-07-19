# Smart Inventory 📱

> **Effortless Inventory Management - Count Smarter, Not Harder**

A comprehensive offline-first inventory management app built with SwiftUI and SwiftData, designed for businesses and individuals who need to track their inventory efficiently without relying on internet connectivity.

## 🎯 App Overview

Smart Inventory is a modern, intuitive inventory management solution that helps you:

- **Track Items Across Multiple Storage Areas**: Organize your inventory by warehouses, rooms, shelves, or any custom storage locations
- **Monitor Stock Levels**: Real-time tracking of quantities with low stock and out-of-stock alerts
- **Manage Costs**: Track unit costs and calculate total values in multiple currencies
- **Work Offline**: Full functionality without internet connectivity using local data storage
- **Search & Filter**: Quickly find items with powerful search and filtering capabilities

## ✨ Key Features

### 🏪 Storage Management
- Create unlimited storage areas with custom names and locations
- Color-coded storage areas for visual organization
- Track total items and quantities per storage
- View detailed storage analytics

### 📦 Item Management
- Add items with detailed information (name, SKU, barcode, description)
- Support for multiple Units of Measurement (UOM)
- Quantity tracking with minimum/maximum thresholds
- Cost tracking with automatic total value calculation
- Out-of-stock and low-stock status indicators

### 📊 Dashboard & Analytics
- Real-time inventory statistics
- Recent activity tracking
- Low stock alerts and notifications
- Out-of-stock item monitoring
- Visual charts and progress indicators

### 💱 Multi-Currency Support
- Support for 20+ world currencies
- Automatic currency formatting
- Persistent currency selection
- Real-time value calculations

### 🔍 Search & Filter
- Global search across all items
- Filter by storage location
- Advanced search with multiple criteria
- Instant results with live updates

### 📤 Export & Reports
- Export inventory summaries to CSV (Excel) or PDF
- Generate low stock and reorder lists
- Professional formatted reports with timestamps
- Share files via AirDrop, email, or cloud storage

## 🛠 Technical Architecture

### Technology Stack
- **Framework**: SwiftUI (iOS 17+)
- **Database**: SwiftData (Core Data successor)
- **Architecture**: MVVM with ObservableObject pattern
- **Storage**: Local SQLite database via SwiftData
- **UI**: Native iOS components with custom styling

### Core Models

#### 1. Storage Model
```swift
@Model
class Storage {
    var id: UUID
    var name: String
    var location: String
    var color: String // Hex color for UI
    var createdAt: Date
    var updatedAt: Date
    
    // Computed properties
    var items: [InventoryItem]
    var itemCount: Int
    var totalQuantity: Double
}
```

#### 2. InventoryItem Model
```swift
@Model
class InventoryItem {
    var id: UUID
    var name: String
    var itemDescription: String
    var sku: String
    var barcode: String
    var currentQuantity: Double
    var minQuantity: Double
    var maxQuantity: Double
    var unitCost: Double
    var isOutOfStock: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    var storage: Storage?
    var uom: UOM?
    var inventoryCounts: [InventoryCount]
}
```

#### 3. UOM (Unit of Measurement) Model
```swift
@Model
class UOM {
    var id: UUID
    var name: String
    var symbol: String
    var category: String
    var isDefault: Bool
    var createdAt: Date
}
```

#### 4. Currency System
```swift
struct Currency: Identifiable, Codable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let symbol: String
}
```

### App Structure

```
AITest/
├── Models/
│   ├── Storage.swift          # Storage area data model
│   ├── InventoryItem.swift    # Item data model
│   ├── UOM.swift             # Units of measurement
│   ├── Currency.swift        # Currency definitions
│   ├── InventoryCount.swift  # Counting history
│   ├── AdManager.swift       # Advertisement system
│   └── ExportManager.swift   # Export functionality
├── Views/
│   ├── SplashScreenView.swift    # App launch screen
│   ├── InventoryAppView.swift    # Main app container
│   ├── DashboardView.swift       # Statistics dashboard
│   ├── StorageListView.swift     # Storage management
│   ├── StorageDetailView.swift   # Individual storage
│   ├── ItemListView.swift        # Item management
│   ├── SettingsView.swift        # App settings
│   └── ExportView.swift          # Export functionality
├── Assets.xcassets/
│   └── AppIcon.appiconset/       # App icon assets
└── Supporting Files/
    ├── AITestApp.swift           # App entry point
    ├── ContentView.swift         # Root view
    └── Item.swift               # Legacy model
```

### Data Flow Architecture

1. **SwiftData Integration**: All data operations use SwiftData's `@Model` and `@Query` property wrappers
2. **Reactive UI**: Views automatically update when underlying data changes
3. **Offline-First**: All data stored locally with no network dependencies
4. **Memory Management**: Efficient data loading with lazy loading where appropriate

## 🚀 Installation & Setup

### Requirements
- iOS 17.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Setup Instructions

1. **Clone the Repository**
   ```bash
   git clone [repository-url]
   cd Smart-Inventory
   ```

2. **Open in Xcode**
   ```bash
   open AITest.xcodeproj
   ```

3. **Build and Run**
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

### Default Data
The app comes with:
- 10 pre-configured Units of Measurement
- 20+ world currencies
- Clean database ready for your data

## 📱 Usage Guide

### Getting Started
1. **Launch the App**: Watch the animated splash screen
2. **Create Storage Areas**: Start by adding your first storage location
3. **Add Items**: Begin adding items to your storage areas
4. **Monitor Dashboard**: View real-time statistics and alerts

### Storage Management
- **Add Storage**: Tap the "+" button in the Storage tab
- **Color Coding**: Choose colors to visually organize storage areas
- **Edit Storage**: Tap on any storage to view/edit details
- **Track Usage**: Monitor item counts and quantities per storage

### Item Management
- **Add Items**: Use the "+" button to add new inventory items
- **Set Thresholds**: Configure minimum and maximum quantities
- **Track Costs**: Add unit costs for value calculations
- **Monitor Status**: View stock levels with color-coded indicators

### Advanced Features
- **Search**: Use the search bar to find items quickly
- **Filter**: Filter items by storage location
- **Currency**: Change currency in Settings
- **Export**: Export data for reporting and analysis

### Export & Reporting
- **Access Export**: Tap the export icon (📤) in Dashboard or Items tab
- **Select Report Type**: Choose from Inventory Summary, Low Stock List, or Reorder List
- **Choose Format**: Export as CSV (Excel) or PDF
- **Share Files**: Use iOS share sheet to send via email, AirDrop, or cloud storage
- **File Naming**: Automatic timestamp-based file naming for organization

## 🔧 Configuration

### Currency Settings
1. Navigate to Settings tab
2. Select your preferred currency
3. All monetary values will update automatically

### UOM Management
The app includes standard units:
- **Weight**: kg, g, lb, oz
- **Volume**: L, mL, gal, fl oz
- **Length**: m, cm, ft, in
- **Count**: pcs, box

### Debug Features
In debug builds, you can:
- Test advertisement system
- View detailed logging
- Access development tools

## 📊 App Store Screenshots

### Screenshot 1: Dashboard Overview
*Shows the main dashboard with key statistics, recent activity, and stock alerts*

### Screenshot 2: Storage Management
*Displays storage areas with color coding and item counts*

### Screenshot 3: Item Management
*Shows the item list with search functionality and stock status indicators*

### Screenshot 4: Item Details
*Detailed view of individual items with all information and actions*

### Screenshot 5: Settings & Currency
*Settings screen showing currency selection and app configuration*

## 🎨 Design System

### Color Palette
- **Primary**: Blue (#007AFF) - iOS standard blue
- **Success**: Green (#34C759) - For in-stock items
- **Warning**: Orange (#FF9500) - For low stock alerts
- **Error**: Red (#FF3B30) - For out-of-stock items
- **Background**: System backgrounds for light/dark mode

### Typography
- **Headers**: San Francisco Bold
- **Body**: San Francisco Regular
- **Monospace**: SF Mono (for SKUs, barcodes)

### Icons
- SF Symbols for consistent iOS experience
- Custom inventory-themed icons for branding

## 🔮 Future Enhancements

### Planned Features
- [ ] **Barcode Scanning**: Camera integration for quick item addition
- [ ] **Multi-location**: Support for multiple warehouses
- [ ] **User Management**: Multi-user support with permissions
- [ ] **Notifications**: Smart alerts for low stock and expiration
- [ ] **Cloud Sync**: Optional cloud backup and synchronization

### Technical Improvements
- [ ] **Unit Tests**: Comprehensive test coverage
- [ ] **UI Tests**: Automated UI testing
- [ ] **Performance**: Optimize for large datasets
- [ ] **Accessibility**: Enhanced VoiceOver support
- [ ] **Localization**: Multi-language support

## 🤝 Contributing

We welcome contributions! Please read our contributing guidelines and submit pull requests for any improvements.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Apple for SwiftUI and SwiftData frameworks
- SF Symbols for the comprehensive icon set
- The iOS development community for inspiration and best practices

---

**Smart Inventory** - Making inventory management effortless, one item at a time.

*Built with ❤️ using SwiftUI* 