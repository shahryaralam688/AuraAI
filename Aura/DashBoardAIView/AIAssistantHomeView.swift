import SwiftUI
import Combine
import Foundation

struct AIAssistantHomeView: View {
    @StateObject private var apiService = APIService.shared
    @StateObject private var voiceClient = WebRTCVoiceClient(backendBaseURL: URL(string: "https://dev.api.limitless-lighting.co.uk")!)
    
    @State private var textInput = ""
    @State private var isVoiceActive = false
    @State private var pulseAnimation = false
    @State private var glowAnimation = false
    @State private var showDashboard = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.05, blue: 0.08),
                            Color(red: 0.05, green: 0.08, blue: 0.12),
                            Color(red: 0.08, green: 0.12, blue: 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Top Section with Logo
                        VStack(spacing: 20) {
                            // Company Logo
                            Image("logoSplash")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .padding(.top, 60)
                            
                            // Voice Button and Text Input
                            HStack(spacing: 16) {
                                // Glowing Siri-style Voice Button
                                Button(action: toggleVoiceAssistant) {
                                    ZStack {
                                        // Outer glow rings
                                        if isVoiceActive {
                                            ForEach(0..<3, id: \.self) { index in
                                                Circle()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [emerald.opacity(0.6), charlesGreen.opacity(0.3)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 2
                                                    )
                                                    .frame(width: 60 + CGFloat(index * 20), height: 60 + CGFloat(index * 20))
                                                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                                    .opacity(pulseAnimation ? 0.3 : 0.8)
                                                    .animation(
                                                        .easeInOut(duration: 1.5)
                                                        .repeatForever(autoreverses: true)
                                                        .delay(Double(index) * 0.2),
                                                        value: pulseAnimation
                                                    )
                                            }
                                        }
                                        
                                        // Main button
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [
                                                        Color(red: 0.15, green: 0.2, blue: 0.25),
                                                        Color(red: 0.08, green: 0.12, blue: 0.16)
                                                    ],
                                                    center: .center,
                                                    startRadius: 10,
                                                    endRadius: 30
                                                )
                                            )
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [alabaster.opacity(0.3), Color.clear],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                            .shadow(
                                                color: isVoiceActive ? emerald.opacity(0.8) : alabaster.opacity(0.2),
                                                radius: isVoiceActive ? 20 : 10,
                                                x: 0,
                                                y: 0
                                            )
                                        
                                        // Microphone icon
                                        Image(systemName: microphoneIcon)
                                            .font(.system(size: 24, weight: .medium))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: isVoiceActive ? [emerald, charlesGreen] : [eton, charlesGreen],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                }
                                .scaleEffect(isVoiceActive ? 1.05 : 1.0)
                                                                
                                // Text Input Field
                                HStack {
                                    TextField("Type your request...", text: $textInput)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(.ultraThinMaterial)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 30)
                                                        .fill(Color.white.opacity(0.05))
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: [Color.white.opacity(0.2), Color.clear],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1
                                                        )
                                                )
                                        )
                                    
                                    if !textInput.isEmpty {
                                        Button(action: sendTextRequest) {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [emerald, charlesGreen],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        .padding(.trailing, 8)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Spacer()
                        
                        // Bottom Section with Greeting and Dashboard Button
                        VStack(spacing: 24) {
                            // User Greeting
                            VStack(spacing: 8) {
                                if apiService.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(eton)
                                        Text("Loading...")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(eton)
                                    }
                                } else {
                                    Text(apiService.getGreetingText())
                                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [alabaster, eton],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color.white.opacity(0.3), radius: 5, x: 0, y: 0)
                                }
                                
                                if let errorMessage = apiService.errorMessage {
                                    Text(errorMessage)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                            }
                            
                            // Dashboard Navigation Button
                            Button(action: { showDashboard = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "chart.bar.doc.horizontal")
                                        .font(.system(size: 20, weight: .medium))
                                    
                                    Text("View Dashboard")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(
                                            LinearGradient(
                                                colors: [emerald.opacity(0.8), charlesGreen.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 25)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.3), Color.clear],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                                .shadow(
                                    color: emerald.opacity(0.4),
                                    radius: 15,
                                    x: 0,
                                    y: 5
                                )
                            }
                            .scaleEffect(glowAnimation ? 1.02 : 1.0)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowAnimation)
                        }
                        .padding(.bottom, 60)
                    }
                }
            }
            .onAppear {
                setupInitialState()
            }
            .onChange(of: voiceClient.state) { _, newState in
                handleVoiceStateChange(newState)
            }
            .sheet(isPresented: $showDashboard) {
                DashboardView()
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Color Definitions (using extensions)
    private var charlesGreen: Color { Color(red: 23.0/255.0, green: 29.0/255.0, blue: 30.0/255.0) } // Charleston Green
    private var eton: Color { Color(red: 147.0/255.0, green: 207.0/255.0, blue: 162.0/255.0) }      // Eton
    private var emerald: Color { Color(red: 84.0/255.0, green: 187.0/255.0, blue: 116.0/255.0) }   // Emerald
    private var alabaster: Color { Color(red: 243.0/255.0, green: 235.0/255.0, blue: 226.0/255.0) }
    
    // MARK: - Computed Properties
    private var microphoneIcon: String {
        switch voiceClient.state {
        case .connected:
            return "mic.fill"
        case .connecting:
            return "mic.badge.plus"
        case .error:
            return "mic.slash.fill"
        case .disconnected:
            return "mic"
        }
    }
    
    // MARK: - Actions
    private func setupInitialState() {
        // Start subtle glow animation
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowAnimation = true
        }
        
        // Set a demo token for testing - replace with actual token from login
        apiService.setUserToken("demo_token_123")
    }
    
    private func toggleVoiceAssistant() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if voiceClient.state == .connected || voiceClient.state == .connecting {
                voiceClient.stop()
                isVoiceActive = false
                pulseAnimation = false
            } else {
                voiceClient.start()
                isVoiceActive = true
                pulseAnimation = true
            }
        }
    }
    
    private func sendTextRequest() {
        let request = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        
        // Here you would typically send the request to your backend
        print("Sending text request: \(request)")
        
        // Clear the input
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            textInput = ""
        }
        
        // Show feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func handleVoiceStateChange(_ newState: VoiceConnectionState) {
        switch newState {
        case .connected:
            isVoiceActive = true
            pulseAnimation = true
        case .disconnected, .error:
            isVoiceActive = false
            pulseAnimation = false
        case .connecting:
            isVoiceActive = true
            pulseAnimation = true
        }
    }
}

#Preview {
    AIAssistantHomeView()
        .preferredColorScheme(.dark)
}
