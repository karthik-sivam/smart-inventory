import SwiftUI

struct SmartSalesEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var showingVoice = false
    @State private var showingPhoto = false
    @State private var showingText = false
    @State private var showingCSV = false
    @State private var showingPDF = false
    @State private var showingPaywall = false
    @State private var activeSaleMode: String?
    @State private var saleEntryOpenedAt = Date()
    @State private var didEmitSaleTerminal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    modeCards
                    if !canUseSmartSales { proUpsellBanner }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Smart Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            AnalyticsManager.shared.track(.smartSalesOpened)
        }
        .sheet(isPresented: $showingVoice, onDismiss: {
            emitSaleAbandonedIfNeeded(mode: "voice", stage: "cancelled")
        }) {
            SmartSalesVoiceView(onCompleted: { count in completeSaleEntry(mode: "voice", itemCount: count) })
                .environmentObject(currencyManager).sheetStyle()
        }
        .sheet(isPresented: $showingPhoto, onDismiss: {
            emitSaleAbandonedIfNeeded(mode: "photo", stage: "cancelled")
        }) {
            SmartSalesPhotoView(onCompleted: { count in completeSaleEntry(mode: "photo", itemCount: count) })
                .environmentObject(currencyManager).sheetStyle()
        }
        .sheet(isPresented: $showingText, onDismiss: {
            emitSaleAbandonedIfNeeded(mode: "text", stage: "cancelled")
        }) {
            SmartSalesTextView(onCompleted: { count in completeSaleEntry(mode: "text", itemCount: count) })
                .environmentObject(currencyManager).sheetStyle()
        }
        .sheet(isPresented: $showingCSV, onDismiss: {
            emitSaleAbandonedIfNeeded(mode: "csv", stage: "cancelled")
        }) {
            SmartSalesCSVView(onCompleted: { count in completeSaleEntry(mode: "csv", itemCount: count) })
                .environmentObject(currencyManager).sheetStyle()
        }
        .sheet(isPresented: $showingPDF, onDismiss: {
            emitSaleAbandonedIfNeeded(mode: "pdf", stage: "cancelled")
        }) {
            SmartSalesPDFView(onCompleted: { count in completeSaleEntry(mode: "pdf", itemCount: count) })
                .environmentObject(currencyManager).sheetStyle()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "smart_sales").sheetStyle()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Color.stoqlyPrimary)
            Text("Smart Sales Entry")
                .font(.title2).fontWeight(.bold)
            Text("Record multiple sales at once using voice, photo, text, or file import. AI parses the input — you review before anything is saved.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var modeCards: some View {
        VStack(spacing: 12) {
            modeCard(icon: "mic.fill", iconColor: .stoqlyPrimary, title: "Voice",
                     description: "Say what you sold. \"5 chips, 2 waters, 1 sandwich\". AI parses into a sale list.",
                     accessibilityId: "voice",
                     action: { openSaleMode("voice") { showingVoice = true } })
            modeCard(icon: "camera.fill", iconColor: .stoqlyAccent, title: "Photo",
                     description: "Photograph a handwritten chit, receipt, or invoice. AI reads every line.",
                     accessibilityId: "photo",
                     action: { openSaleMode("photo") { showingPhoto = true } })
            modeCard(icon: "text.alignleft", iconColor: .blue, title: "Text",
                     description: "Type or paste a free-form sales list. AI structures it for you.",
                     accessibilityId: "text",
                     action: { openSaleMode("text") { showingText = true } })
            modeCard(icon: "tablecells", iconColor: .green, title: "CSV / Excel",
                     description: "Import a spreadsheet of sales. Map columns then confirm.",
                     accessibilityId: "csv_excel",
                     action: { openSaleMode("csv") { showingCSV = true } })
            modeCard(icon: "doc.fill", iconColor: .orange, title: "PDF",
                     description: "Upload a PDF invoice or sales report. AI extracts the sale rows.",
                     accessibilityId: "pdf",
                     action: { openSaleMode("pdf") { showingPDF = true } })
        }
    }

    private func openSaleMode(_ mode: String, action: () -> Void) {
        guard canUseSmartSales else {
            showingPaywall = true
            return
        }
        activeSaleMode = mode
        saleEntryOpenedAt = Date()
        didEmitSaleTerminal = false
        AnalyticsManager.shared.track(.saleEntryStarted(mode: mode))
        action()
    }

    private func completeSaleEntry(mode: String, itemCount: Int) {
        guard activeSaleMode == mode, !didEmitSaleTerminal else { return }
        didEmitSaleTerminal = true
        AnalyticsManager.shared.track(
            .saleEntryCompleted(
                mode: mode,
                itemCount: itemCount,
                durationMs: max(0, Int(Date().timeIntervalSince(saleEntryOpenedAt) * 1_000))
            )
        )
        dismiss()
    }

    private func emitSaleAbandonedIfNeeded(mode: String, stage: String) {
        guard activeSaleMode == mode, !didEmitSaleTerminal else { return }
        didEmitSaleTerminal = true
        AnalyticsManager.shared.track(.saleEntryAbandoned(mode: mode, stage: stage))
        AnalyticsManager.shared.track(.saleEntryCancelled(mode: mode))
    }

    private func modeCard(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        let isPro = canUseSmartSales
        return Button(action: isPro ? action : { showingPaywall = true }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(iconColor.opacity(isPro ? 0.12 : 0.06)).frame(width: 52, height: 52)
                    Image(systemName: icon).font(.title3).foregroundColor(isPro ? iconColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(isPro ? .primary : .secondary)
                        if !isPro {
                            Text("PRO").font(.caption2).fontWeight(.bold).foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange).cornerRadius(4)
                        }
                    }
                    Text(description).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isPro ? "chevron.right" : "lock.fill")
                    .font(.caption).foregroundColor(isPro ? .secondary : .orange)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .opacity(isPro ? 1.0 : 0.7)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("smartSalesMode_\(accessibilityId)")
    }

    private var canUseSmartSales: Bool {
        subscriptionManager.isPro || SmartReviewFixture.isSmartSalesEnabled
    }

    private var proUpsellBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Smart Sales Entry is a Pro feature").font(.subheadline).fontWeight(.semibold)
                Text("Upgrade to record bulk sales with AI — saves hours of manual entry.").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Upgrade") { showingPaywall = true }.font(.caption).fontWeight(.semibold).foregroundColor(.orange)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
