import SwiftUI

// MARK: - OnboardingView
//
// Shown on first app launch (before auth).
// 4 pages covering the app's core value propositions.
// Stored flag in UserDefaults so it only shows once.

struct OnboardingView: View {

    @Binding var isPresented: Bool

    @State private var currentPage = 0
    @State private var animateContent = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "cube.box.fill",
            iconColors: [.blue, .cyan],
            title: "Know What You Have",
            subtitle: "Track every product, ingredient, or supply across all your storage areas — in real time.",
            accentColor: .blue
        ),
        OnboardingPage(
            icon: "archivebox.fill",
            iconColors: [.purple, .pink],
            title: "Organise by Location",
            subtitle: "Warehouse, shelf, fridge, storeroom — create as many storage areas as your business needs.",
            accentColor: .purple
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColors: [.orange, .red],
            title: "Never Run Out",
            subtitle: "Set minimum thresholds and get alerted when stock runs low before it hits zero.",
            accentColor: .orange
        ),
        OnboardingPage(
            icon: "icloud.fill",
            iconColors: [.green, .teal],
            title: "Your Data, Everywhere",
            subtitle: "Start free on one device. Upgrade to Pro for cloud sync, AI insights, and team collaboration.",
            accentColor: .green
        )
    ]

    var body: some View {
        ZStack {
            // Background gradient tied to current page colour
            LinearGradient(
                colors: [
                    pages[currentPage].accentColor.opacity(0.15),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") { finishOnboarding() }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }

                Spacer()

                // Page content — use TabView for swipe gesture support
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page, pageIndex: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 420)
                .animation(.easeInOut, value: currentPage)

                Spacer()

                VStack(spacing: 24) {
                    // Page dots
                    PageIndicator(total: pages.count, current: currentPage, accentColor: pages[currentPage].accentColor)

                    // Primary action button
                    Button(action: handlePrimaryAction) {
                        Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: pages[currentPage].iconColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 32)
                    .animation(.spring(response: 0.3), value: currentPage)

                    if currentPage == pages.count - 1 {
                        Text("No credit card required. Free forever.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        if currentPage < pages.count - 1 {
            withAnimation(.spring(response: 0.4)) {
                currentPage += 1
            }
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - OnboardingPageView

struct OnboardingPageView: View {

    let page: OnboardingPage
    let pageIndex: Int
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 32) {
            // Icon with gradient circle background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.iconColors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: page.icon)
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: page.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(didAppear ? 1 : 0.6)
            .opacity(didAppear ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: didAppear)

            VStack(spacing: 12) {
                // Keep title/subtitle fully opaque so VoiceOver & UI tests see them immediately
                // (alpha 0 removes elements from the accessibility tree and breaks Maestro).
                Text(page.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding.title.\(pageIndex)")
                    .offset(y: didAppear ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: didAppear)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .offset(y: didAppear ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: didAppear)
            }
        }
        .padding()
        .onAppear {
            didAppear = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                didAppear = true
            }
        }
        .onDisappear { didAppear = false }
    }
}

// MARK: - Page Indicator

struct PageIndicator: View {
    let total: Int
    let current: Int
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? accentColor : Color(.systemGray4))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
    }
}

// MARK: - Data Model

struct OnboardingPage {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String
    let accentColor: Color
}

// MARK: - Convenience: check if onboarding needed

extension UserDefaults {
    static var hasCompletedOnboarding: Bool {
        standard.bool(forKey: "onboarding_completed")
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
