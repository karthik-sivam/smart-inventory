import SwiftUI
import SwiftData

/// S33 Phase 1 — configurable notification preferences (local digest + Firestore sync).
struct NotificationSettingsView: View {
    @ObservedObject private var prefsManager = NotificationPrefsManager.shared
    @Query private var items: [InventoryItem]

    @State private var preferredTime: Date = NotificationPrefsManager.shared.prefs.preferredTimeDate

    var body: some View {
        Form {
            Section {
                Toggle(L("notifications.master", "Notifications"), isOn: masterBinding)
            } footer: {
                Text(L("notifications.master.footer", "Turn off to stop daily digests. Announcements from Stoqly can still appear if enabled below."))
            }

            if prefsManager.prefs.masterEnabled {
                Section(header: Text(L("notifications.daily.header", "Daily digest"))) {
                    Toggle(L("notifications.lowStock", "Low stock summary"), isOn: lowStockBinding)
                    Toggle(L("notifications.expiry", "Expiring items summary"), isOn: expiryBinding)
                    DatePicker(
                        L("notifications.preferredTime", "Notify at"),
                        selection: $preferredTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: preferredTime) { _, newTime in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                        prefsManager.update {
                            $0.preferredHour = parts.hour ?? 18
                            $0.preferredMinute = parts.minute ?? 0
                        }
                    }
                }

                Section(header: Text(L("notifications.future.header", "Coming soon (server push)"))) {
                    Toggle(L("notifications.weekly", "Weekly business summary"), isOn: weeklyBinding)
                        .disabled(true)
                    Toggle(L("notifications.monthly", "Monthly stock count reminder"), isOn: monthlyBinding)
                        .disabled(true)
                }

                Section(header: Text(L("notifications.instant.header", "Instant"))) {
                    Toggle(L("notifications.announcements", "Announcements & offers"), isOn: announcementsBinding)
                }
            }

            Section(footer: Text(L("notifications.phase1.footer", "Phase 1: one combined on-device digest per day. Server-scheduled pushes will replace this after backend deploy."))) {
                EmptyView()
            }
        }
        .navigationTitle(L("notifications.title", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            preferredTime = prefsManager.prefs.preferredTimeDate
            refreshDigest()
        }
        .onChange(of: items.count) { _, _ in refreshDigest() }
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.masterEnabled },
            set: { enabled in prefsManager.update { $0.masterEnabled = enabled } }
        )
    }

    private var lowStockBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.lowStockDaily },
            set: { enabled in prefsManager.update { $0.lowStockDaily = enabled } }
        )
    }

    private var expiryBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.expiryDaily },
            set: { enabled in prefsManager.update { $0.expiryDaily = enabled } }
        )
    }

    private var weeklyBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.weeklySummary },
            set: { enabled in prefsManager.update { $0.weeklySummary = enabled } }
        )
    }

    private var monthlyBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.monthlyCount },
            set: { enabled in prefsManager.update { $0.monthlyCount = enabled } }
        )
    }

    private var announcementsBinding: Binding<Bool> {
        Binding(
            get: { prefsManager.prefs.announcements },
            set: { enabled in prefsManager.update { $0.announcements = enabled } }
        )
    }

    private func refreshDigest() {
        NotificationManager.shared.refreshLocalDigestSchedule(items: items)
    }
}
