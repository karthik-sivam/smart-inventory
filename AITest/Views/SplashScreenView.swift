import SwiftUI

struct SplashScreenView: View {

    @State private var showingMainApp  = false
    @State private var animateLogo     = false
    @State private var animateTitle    = false
    @State private var animateTagline  = false
    @State private var animatePills    = false
    @State private var animateDots     = false

    // Adaptive brand palette — explicit Any/Dark values live in Assets.xcassets.
    private let bgTop    = Color("SplashBackgroundTop")
    private let bgBottom = Color("SplashBackgroundBottom")
    private let teal     = Color("SplashAccent")
    private let gold     = Color("SplashGold")

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [bgTop, bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radial glow behind the icon
            Circle()
                .fill(teal.opacity(0.07))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(y: -40)

            VStack(spacing: 0) {
                Spacer()

                // ── Brand mark ──────────────────────────────────────────────
                VStack(spacing: 22) {

                    // Icon circle
                    ZStack {
                        Circle()
                            .fill(teal.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Circle()
                            .stroke(teal.opacity(0.25), lineWidth: 1)
                            .frame(width: 96, height: 96)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [teal, gold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .scaleEffect(animateLogo ? 1.0 : 0.55)
                    .opacity(animateLogo ? 1.0 : 0.0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.15), value: animateLogo)

                    // Wordmark
                    Text("Stoqly")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(animateTitle ? 1.0 : 0.0)
                        .offset(y: animateTitle ? 0 : 10)
                        .animation(.easeOut(duration: 0.55).delay(0.50), value: animateTitle)

                    // Taglines
                    VStack(spacing: 6) {
                        Text("Effortless Inventory Management")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(gold)
                            .opacity(animateTagline ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.45).delay(0.85), value: animateTagline)

                        Text("Count smarter, not harder")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color("SplashSecondaryText"))
                            .opacity(animateTagline ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.45).delay(1.05), value: animateTagline)
                    }
                }

                Spacer()

                // ── Feature pills ───────────────────────────────────────────
                HStack(spacing: 10) {
                    featurePill(icon: "barcode.viewfinder", label: "Scan")
                    featurePill(icon: "mic.fill",           label: "Voice")
                    featurePill(icon: "camera.fill",        label: "Photo")
                    featurePill(icon: "sparkles",           label: "AI")
                }
                .opacity(animatePills ? 1.0 : 0.0)
                .offset(y: animatePills ? 0 : 8)
                .animation(.easeOut(duration: 0.45).delay(1.25), value: animatePills)

                Spacer()

                // ── Loading indicator ───────────────────────────────────────
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 0 ? gold : teal.opacity(0.55))
                            .frame(width: index == 0 ? 20 : 6, height: 4)
                            .scaleEffect(x: animateDots ? 1.0 : 0.4)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.18 + 1.5),
                                value: animateDots
                            )
                    }
                }
                .padding(.bottom, 52)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            animateLogo    = true
            animateTitle   = true
            animateTagline = true
            animatePills   = true
            animateDots    = true

            // Transition to main app after 3 s (shorter than original 4 s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.7)) {
                    showingMainApp = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingMainApp) {
            InventoryAppView()
        }
    }

    private func featurePill(icon: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(teal)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("SplashSecondaryText"))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color("SplashPillSurface"))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(teal.opacity(0.28), lineWidth: 1))
    }
}

#Preview {
    SplashScreenView()
}
