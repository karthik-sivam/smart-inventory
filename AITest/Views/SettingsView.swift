import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Currency")) {
                    Picker("Currency", selection: $currencyManager.selectedCurrency) {
                        ForEach(Currency.currencies, id: \.code) { currency in
                            CurrencyRow(currency: currency)
                                .tag(currency)
                        }
                    }
                    .pickerStyle(NavigationLinkPickerStyle())
                    .onChange(of: currencyManager.selectedCurrency) { _, _ in
                        // Track completion for ad system
                        AdManager.shared.recordCompletion(event: .settingsChanged)
                    }
                }
                
#if DEBUG
                Section(header: Text("Debug - Advertisement")) {
                    Button(action: {
                        AdManager.shared.showTestAd(type: .interstitial)
                    }) {
                        HStack {
                            Label("Test Interstitial Ad", systemImage: "rectangle.stack")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        AdManager.shared.showTestAd(type: .banner)
                    }) {
                        HStack {
                            Label("Test Banner Ad", systemImage: "rectangle.bottomthird.inset.filled")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // TODO: PREMIUM FEATURE - Reward ads for premium features
                    // Temporarily disabled until premium features are ready
                    /*
                    Button(action: {
                        AdManager.shared.showTestAd(type: .reward)
                    }) {
                        HStack {
                            Label("Test Reward Ad", systemImage: "gift")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    */
                    
                    // Placeholder for future premium features
                    HStack {
                        Label("Premium Features (Coming Soon)", systemImage: "star.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Text("Soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
#endif
                
                Section(header: Text("About")) {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("App", systemImage: "cube.box")
                        Spacer()
                        Text("Smart Inventory")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Account")) {
                    Button(action: {
                        AuthManager.shared.signOut()
                    }) {
                        HStack {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
}

struct CurrencyRow: View {
    let currency: Currency
    
    var body: some View {
        HStack {
            Text(currency.symbol)
                .frame(width: 30, alignment: .leading)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(currency.name)
                    .font(.headline)
                Text(currency.code)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CurrencyManager())
} 