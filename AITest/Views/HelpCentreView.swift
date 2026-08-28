import SwiftUI

struct HelpCentreView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var searchText = ""
    @State private var expandedID: UUID?
    @State private var aiQuestion = ""
    @State private var aiAnswer: String?
    @State private var isAsking = false
    @State private var aiError: String?
    @State private var showPaywall = false
    @State private var showFeedback = false

    private struct FAQItem: Identifiable {
        let id = UUID()
        let section: String
        let question: LocalizedStringKey
        let answer: LocalizedStringKey

        var sectionTitle: LocalizedStringKey {
            switch section {
            case "Getting Started": "Getting Started"
            case "SmartCount": "SmartCount"
            case "Reorder Alerts": "Reorder Alerts"
            case "Reports": "Reports"
            case "Pro": "Pro"
            default: LocalizedStringKey(section)
            }
        }
    }

    private let suggestedQuestions: [String] = [
        L("help.suggested.addItem", "How do I add a new item?"),
        L("help.suggested.freeVsPro", "What is the difference between Free and Pro?"),
        L("help.suggested.photoInventory", "How do Photo Inventory counts work?"),
        L("help.suggested.lowStock", "How do I set a low stock alert?"),
        L("help.suggested.teamMembers", "How do I add my team members?"),
    ]

    private let allItems: [FAQItem] = [
        FAQItem(section: "Getting Started",
                question: "How do I add my first product?",
                answer: "Go to any Storage, tap the + button, and fill in the item details. You can scan a barcode to auto-fill the name and details."),
        FAQItem(section: "Getting Started",
                question: "What is a Storage?",
                answer: "A Storage is a location in your business — a shelf, room, freezer, or section. Add storages to organise your inventory by location."),
        FAQItem(section: "Getting Started",
                question: "Is Stoqly free?",
                answer: "Yes — Stoqly is free to use with up to 5 storages and 50 items per storage. Upgrade to Pro for unlimited storages, items, and advanced analytics."),
        FAQItem(section: "SmartCount",
                question: "How does Photo Inventory work?",
                answer: "Open SmartCount — Photo. Point your camera at a shelf or product. Stoqly uses AI to identify items and their quantities automatically."),
        FAQItem(section: "SmartCount",
                question: "How does Voice Inventory work?",
                answer: "Open SmartCount — Voice. Tap the microphone and say your items aloud, e.g. 'Rice 5kg, cooking oil 2 bottles'. The AI extracts and adds them."),
        FAQItem(section: "SmartCount",
                question: "Can it detect how much liquid is left in a bottle?",
                answer: "Yes — in Photo mode, toggle 'Measuring fluid level' before scanning. Stoqly will estimate the fill level and remaining volume."),
        FAQItem(section: "Reorder Alerts",
                question: "How do I set a low-stock alert?",
                answer: "Edit any item and set a Minimum Quantity. You'll get a push notification when stock drops below that level."),
        FAQItem(section: "Reorder Alerts",
                question: "What is a reorder percentage?",
                answer: "Instead of a fixed quantity, you can set a percentage — e.g. 20% means you're alerted when stock falls below 20% of your maximum."),
        FAQItem(section: "Reports",
                question: "Where do I see my profits?",
                answer: "On the Dashboard, scroll down to the Smart Insights card. Set a selling price and cost price on your items to unlock profit tracking."),
        FAQItem(section: "Reports",
                question: "How do I export my inventory?",
                answer: "Go to Settings — Export. You can export as CSV or PDF."),
        FAQItem(section: "Pro",
                question: "What does Pro include?",
                answer: "Unlimited storages and items, full analytics history, barcode scanner pro, bulk CSV import, and no ads."),
        FAQItem(section: "Pro",
                question: "How do I upgrade to Pro?",
                answer: "Go to Settings — Upgrade to Pro to unlock all features instantly."),
    ]

    private var filteredItems: [FAQItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter {
            $0.section.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedSections: [(String, [FAQItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: \.section)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groupedSections, id: \.0) { _, items in
                Section(items.first?.sectionTitle ?? "") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.question)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if expandedID == item.id {
                                Text(item.answer)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            expandedID = expandedID == item.id ? nil : item.id
                        }
                    }
                }
            }

            Section(header: Text("Ask AI")) {
                aiChatSection
            }

            Section(header: Text(L("feedback.contact.header", "Contact"))) {
                Button {
                    showFeedback = true
                } label: {
                    Label(L("feedback.send", "Send Feedback"), systemImage: "text.bubble")
                }
                .accessibilityIdentifier("sendFeedbackRow")

                Button {
                    openEmailSupport()
                } label: {
                    Label(L("feedback.emailSupport", "Email Support"), systemImage: "envelope")
                }
                .accessibilityIdentifier("emailSupportRow")
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search help topics")
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "help_chat").sheetStyle()
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
                .environmentObject(AuthManager.shared)
                .sheetStyle()
        }
    }

    private func openEmailSupport() {
        let subject = L("feedback.email.subject", "Stoqly Feedback")
        let mailtoString = "mailto:\(HelpAndSupport.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: mailtoString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private var aiChatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let remaining = AIUsageManager.shared.remaining(.helpChat, isPro: subscriptionManager.isPro)
            if !subscriptionManager.isPro {
                Text(
                    String(
                        format: L("help.aiQuotaRemaining", "%1$d free question%2$@ remaining this month"),
                        remaining,
                        remaining == 1 ? "" : "s"
                    )
                )
                    .font(.caption)
                    .foregroundColor(remaining == 0 ? .red : .secondary)
            }

            if aiAnswer == nil && aiQuestion.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { q in
                            Button(q) { aiQuestion = q }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(16)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask anything about Stoqly…", text: $aiQuestion, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isAsking)

                Button {
                    Task { await askAI() }
                } label: {
                    if isAsking {
                        ProgressView().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(
                                aiQuestion.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .stoqlyPrimary
                            )
                    }
                }
                .disabled(aiQuestion.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }

            if let answer = aiAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answer)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    Button("Ask another question") {
                        aiQuestion = ""
                        aiAnswer = nil
                        aiError = nil
                    }
                    .font(.caption)
                    .foregroundColor(.stoqlyPrimary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            if let error = aiError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func askAI() async {
        let trimmed = aiQuestion.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        AnalyticsManager.shared.track(.aiHelpQuestionAsked(question: trimmed))

        guard AIUsageManager.shared.canUse(.helpChat, isPro: subscriptionManager.isPro) else {
            if subscriptionManager.isPro {
                aiError = L("help.aiUsageError", "Something went wrong with usage tracking. Please try again.")
            } else {
                showPaywall = true
            }
            return
        }

        isAsking = true
        aiAnswer = nil
        aiError = nil

        let clock = AIRequestClock(
            feature: "ask_ai_help",
            mode: "help",
            inputBytes: trimmed.utf8.count
        )
        do {
            let answer = try await AIInventoryService.shared.askHelpQuestion(trimmed)
            AIUsageManager.shared.recordUse(.helpChat)
            aiAnswer = answer
            let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAnswer.isEmpty {
                clock.empty(reason: "empty_answer")
            } else {
                clock.succeeded(itemCount: 1)
            }
        } catch {
            aiError = error.localizedDescription
            clock.finish(error: error, stage: "receive")
        }

        isAsking = false
    }
}
