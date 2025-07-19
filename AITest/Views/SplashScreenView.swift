import SwiftUI

struct SplashScreenView: View {
    @State private var showingMainApp = false
    @State private var animateTitle = false
    @State private var animateSubtitle = false
    @State private var animateIcon = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.8, blue: 1.0),
                    Color(red: 0.9, green: 0.7, blue: 1.0),
                    Color(red: 1.0, green: 0.8, blue: 0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Text("Smart Inventory")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .opacity(animateTitle ? 1.0 : 0.0)
                    .scaleEffect(animateTitle ? 1.0 : 0.8)
                    .animation(.easeOut(duration: 0.8).delay(0.5), value: animateTitle)
                
                VStack(spacing: 12) {
                    Text("Effortless Inventory Management")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.8))
                        .opacity(animateSubtitle ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.6).delay(1.0), value: animateSubtitle)
                    
                    Text("Count Smarter, Not Harder")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.black.opacity(0.7))
                        .opacity(animateSubtitle ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.6).delay(1.2), value: animateSubtitle)
                }
                
                Spacer()
                
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                            .opacity(animateIcon ? 1.0 : 0.0)
                            .rotationEffect(.degrees(animateIcon ? 0 : -10))
                            .animation(.easeOut(duration: 0.8).delay(1.5), value: animateIcon)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: 60, height: 40)
                                    .opacity(animateIcon ? 1.0 : 0.0)
                                    .scaleEffect(animateIcon ? 1.0 : 0.8)
                                    .animation(.easeOut(duration: 0.6).delay(1.7 + Double.random(in: 0...0.3)), value: animateIcon)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.6)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: 60, height: 50)
                                    .opacity(animateIcon ? 1.0 : 0.0)
                                    .scaleEffect(animateIcon ? 1.0 : 0.8)
                                    .animation(.easeOut(duration: 0.6).delay(2.0 + Double.random(in: 0...0.3)), value: animateIcon)
                            }
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 45, height: 60)
                                .opacity(animateIcon ? 1.0 : 0.0)
                                .scaleEffect(animateIcon ? 1.0 : 0.8)
                                .animation(.easeOut(duration: 0.6).delay(2.2), value: animateIcon)
                        }
                    }
                    
                    HStack(spacing: 2) {
                        ForEach(0..<12, id: \.self) { index in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: index % 3 == 0 ? 3 : 2, height: 30)
                                .opacity(animateIcon ? 1.0 : 0.0)
                                .scaleEffect(y: animateIcon ? 1.0 : 0.1)
                                .animation(.easeOut(duration: 0.4).delay(2.5 + Double(index) * 0.05), value: animateIcon)
                        }
                    }
                    
                    HStack {
                        Text("20027")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .opacity(animateIcon ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.4).delay(3.0), value: animateIcon)
                        
                        Text("074322")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .opacity(animateIcon ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.4).delay(3.1), value: animateIcon)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animateIcon ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2 + 2.0),
                                value: animateIcon
                            )
                    }
                }
                .padding(.bottom, 50)
            }
            .padding()
        }
        .onAppear {
            animateTitle = true
            animateSubtitle = true
            animateIcon = true
            
            // Transition to main app after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    showingMainApp = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingMainApp) {
            InventoryAppView()
        }
    }
}

#Preview {
    SplashScreenView()
} 