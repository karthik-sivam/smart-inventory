import SwiftUI

struct AIHelpChatView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var aiQuestion = ""
    @State private var aiAnswer: String?
    @State private var isAsking = false
    @State private var aiError: String?
    @State private var showPaywall = false

    private let suggestedQuestions = [
        "How do I add a new item?",
        "How does Photo Inventory work?",
        "How do I set a low stock alert?",
        "What's the difference between Free and Pro?",
        "How do I add team members?",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let remaining = AIUsageManager.shared.remaining(.helpChat, isPro: subscriptionManager.isPro)
                    if !subscriptionManager.isPro {
                        Text("\(remaining) free question\(remaining == 1 ? "" : "s") remaining this month")
                            .font(.caption)
                            .foregroundColor(remaining == 0 ? .red : .secondary)
                            .padding(.horizontal)
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
                            .padding(.horizontal)
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
                    .padding(.horizontal)

                    if let answer = aiAnswer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(answer)
                                .font(.subheadline)
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
                        .padding(.horizontal)
                    }

                    if let error = aiError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "help_chat_fab").sheetStyle()
            }
        }
    }

    @MainActor
    private func askAI() async {
        let trimmed = aiQuestion.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard AIUsageManager.shared.canUse(.helpChat, isPro: subscriptionManager.isPro) else {
            showPaywall = true
            return
        }

        isAsking = true
        aiAnswer = nil
        aiError = nil

        do {
            let answer = try await AIInventoryService.shared.askHelpQuestion(trimmed)
            AIUsageManager.shared.recordUse(.helpChat)
            aiAnswer = answer
        } catch {
            aiError = error.localizedDescription
        }

        isAsking = false
    }
}
